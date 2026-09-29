module spi_master #(
    parameter int DATA_WIDTH = 8,
    parameter int CLK_DIV    = 4,
    parameter bit CPOL       = 1'b0,
    parameter bit CPHA       = 1'b0
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  start,
    input  logic [DATA_WIDTH-1:0] tx_data,
    input  logic                  miso,

    output logic                  sclk,
    output logic                  mosi,
    output logic                  cs_n,
    output logic [DATA_WIDTH-1:0] rx_data,
    output logic                  busy,
    output logic                  done
);

    // ============================================================
    // Parameterized widths
    // ============================================================

    localparam int DIV_WIDTH =
        (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);

    localparam int COUNT_WIDTH =
        (DATA_WIDTH <= 1) ? 1 : $clog2(DATA_WIDTH + 1);

    // ============================================================
    // FSM
    // ============================================================

    typedef enum logic [2:0] {
        IDLE,
        ASSERT_CS,
        SHIFT,
        DEASSERT_CS,
        DONE
    } state_t;

    state_t state, next_state;

    // ============================================================
    // Shift registers and counters
    // ============================================================

    logic [DATA_WIDTH-1:0] tx_shreg;
    logic [DATA_WIDTH-1:0] rx_shreg;

    logic [DIV_WIDTH-1:0]   clk_cnt;
    logic [COUNT_WIDTH-1:0] bit_cnt;

    logic spi_tick;

    // ============================================================
    // SPI edge information
    // ============================================================

    logic leading_edge;
    logic trailing_edge;
    logic sample_edge;
    logic shift_edge;

    /*
     * CPOL = 0:
     *   Leading edge  = Rising
     *   Trailing edge = Falling
     *
     * CPOL = 1:
     *   Leading edge  = Falling
     *   Trailing edge = Rising
     */

    always_comb begin

        leading_edge  = (sclk == CPOL);
        trailing_edge = (sclk != CPOL);

        /*
         * CPHA = 0:
         *   Sample on leading edge
         *   Shift on trailing edge
         *
         * CPHA = 1:
         *   Shift on leading edge
         *   Sample on trailing edge
         */

        if (CPHA == 1'b0) begin
            sample_edge = leading_edge;
            shift_edge  = trailing_edge;
        end
        else begin
            sample_edge = trailing_edge;
            shift_edge  = leading_edge;
        end

    end

    // ============================================================
    // SPI clock divider
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin
            clk_cnt <= '0;
        end
        else if (state != SHIFT) begin
            clk_cnt <= '0;
        end
        else if (CLK_DIV <= 1) begin
            clk_cnt <= '0;
        end
        else if (clk_cnt == CLK_DIV-1) begin
            clk_cnt <= '0;
        end
        else begin
            clk_cnt <= clk_cnt + 1'b1;
        end

    end

    assign spi_tick =
        (CLK_DIV <= 1) || (clk_cnt == CLK_DIV-1);

    // ============================================================
    // State register and SPI datapath
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state    <= IDLE;

            tx_shreg <= '0;
            rx_shreg <= '0;

            bit_cnt  <= '0;

            sclk     <= CPOL;
            mosi     <= 1'b0;

            rx_data  <= '0;

        end
        else begin

            state <= next_state;

            // ----------------------------------------------------
            // Load a new transaction
            // ----------------------------------------------------

            if (state == IDLE && start) begin

                tx_shreg <= tx_data;
                rx_shreg <= '0;
                bit_cnt  <= '0;

                /*
                 * For CPHA=0 the first bit must be present before
                 * the first sampling edge.
                 *
                 * Keeping it here also gives the correct initial
                 * value for CPHA=1.
                 */
                mosi <= tx_data[DATA_WIDTH-1];

            end

            // ----------------------------------------------------
            // SHIFT state
            // ----------------------------------------------------

            if (state == SHIFT && spi_tick) begin

                /*
                 * Toggle SCLK.
                 *
                 * The current value of sclk determines whether
                 * the edge being generated is leading or trailing.
                 */
                sclk <= ~sclk;

                // =================================================
                // Sample MISO
                // =================================================

                if (sample_edge) begin

                    rx_shreg <= {
                        rx_shreg[DATA_WIDTH-2:0],
                        miso
                    };

                    bit_cnt <= bit_cnt + 1'b1;

                end

                // =================================================
                // Shift / transmit MOSI
                // =================================================

                if (shift_edge) begin

                    /*
                     * Shift the transmit register MSB-first.
                     */
                    tx_shreg <= {
                        tx_shreg[DATA_WIDTH-2:0],
                        1'b0
                    };

                    /*
                     * Present the next bit on MOSI.
                     */
                    if (bit_cnt < DATA_WIDTH-1)
                        mosi <= tx_shreg[DATA_WIDTH-2];
                    else
                        mosi <= 1'b0;

                end

            end

            // ----------------------------------------------------
            // Return SCLK to idle level
            // ----------------------------------------------------

            if (state == DEASSERT_CS) begin
                sclk <= CPOL;
                rx_data <= rx_shreg;
            end

        end

    end

    // ============================================================
    // FSM next-state logic and outputs
    // ============================================================

    always_comb begin

        next_state = state;

        busy = 1'b0;
        done = 1'b0;

        case (state)

            // ====================================================
            // IDLE
            // ====================================================

            IDLE: begin

                busy = 1'b0;

                if (start)
                    next_state = ASSERT_CS;

            end

            // ====================================================
            // ASSERT CS
            // ====================================================

            ASSERT_CS: begin

                busy = 1'b1;

                next_state = SHIFT;

            end

            // ====================================================
            // SHIFT
            // ====================================================

            SHIFT: begin

                busy = 1'b1;

                /*
                 * CS remains asserted here.
                 *
                 * start is ignored while busy.
                 */

                /*
                 * CPHA = 0:
                 *
                 * Last bit is sampled on the leading edge.
                 * The following trailing edge must occur before
                 * CS is released.
                 */
                if ((CPHA == 1'b0) &&
                    spi_tick &&
                    shift_edge &&
                    (bit_cnt == DATA_WIDTH)) begin

                    next_state = DEASSERT_CS;

                end

                /*
                 * CPHA = 1:
                 *
                 * Last bit is sampled on the trailing edge.
                 */
                else if ((CPHA == 1'b1) &&
                         spi_tick &&
                         sample_edge &&
                         (bit_cnt == DATA_WIDTH-1)) begin

                    next_state = DEASSERT_CS;

                end

            end

            // ====================================================
            // DEASSERT CS
            // ====================================================

            DEASSERT_CS: begin

                busy = 1'b0;

                next_state = DONE;

            end

            // ====================================================
            // DONE
            // ====================================================

            DONE: begin

                busy = 1'b0;
                done = 1'b1;

                next_state = IDLE;

            end

            // ====================================================
            // Default
            // ====================================================

            default: begin

                next_state = IDLE;

            end

        endcase

    end

    // ============================================================
    // CS control
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin
            cs_n <= 1'b1;
        end
        else begin

            case (state)

                IDLE:
                    cs_n <= 1'b1;

                ASSERT_CS:
                    cs_n <= 1'b0;

                SHIFT:
                    cs_n <= 1'b0;

                DEASSERT_CS:
                    cs_n <= 1'b1;

                DONE:
                    cs_n <= 1'b1;

                default:
                    cs_n <= 1'b1;

            endcase

        end

    end

endmodule
