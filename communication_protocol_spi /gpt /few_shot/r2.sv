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
    // Parameterized counter widths
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

    // Used for CPHA=0 after the last sampling edge
    logic finish_pending;

    // ============================================================
    // Clock divider tick
    // ============================================================

    logic spi_tick;

    always_comb begin
        if (CLK_DIV <= 1)
            spi_tick = 1'b1;
        else
            spi_tick = (clk_cnt == CLK_DIV-1);
    end

    // ============================================================
    // SPI edge definitions
    // ============================================================

    logic leading_edge;
    logic trailing_edge;
    logic sample_edge;
    logic shift_edge;

    /*
     * CPOL = 0:
     *     Leading edge  = Rising
     *     Trailing edge = Falling
     *
     * CPOL = 1:
     *     Leading edge  = Falling
     *     Trailing edge = Rising
     */

    always_comb begin

        leading_edge  = (sclk == CPOL);
        trailing_edge = (sclk != CPOL);

        /*
         * CPHA = 0:
         *     Sample on leading edge
         *     Shift on trailing edge
         *
         * CPHA = 1:
         *     Shift on leading edge
         *     Sample on trailing edge
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
    // Sequential logic
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state          <= IDLE;

            tx_shreg       <= '0;
            rx_shreg       <= '0;

            clk_cnt        <= '0;
            bit_cnt        <= '0;
            finish_pending <= 1'b0;

            sclk           <= CPOL;
            mosi           <= 1'b0;
            cs_n           <= 1'b1;

            rx_data        <= '0;

        end
        else begin

            state <= next_state;

            // ----------------------------------------------------
            // Clock divider
            // ----------------------------------------------------

            if (state == SHIFT) begin

                if (spi_tick)
                    clk_cnt <= '0;
                else
                    clk_cnt <= clk_cnt + 1'b1;

            end
            else begin
                clk_cnt <= '0;
            end

            // ----------------------------------------------------
            // Start a new transaction
            // ----------------------------------------------------

            if (state == IDLE && start) begin

                tx_shreg       <= tx_data;
                rx_shreg       <= '0;
                bit_cnt        <= '0;
                finish_pending <= 1'b0;

                /*
                 * CPHA=0 requires the first data bit to be present
                 * before the first leading edge.
                 *
                 * For CPHA=1 the first bit is also stored here,
                 * but it is formally launched on the first
                 * leading edge below.
                 */
                mosi <= tx_data[DATA_WIDTH-1];

            end

            // ----------------------------------------------------
            // SPI transfer
            // ----------------------------------------------------

            if (state == SHIFT && spi_tick) begin

                // Toggle SCLK
                sclk <= ~sclk;

                // ================================================
                // CPHA = 0
                // ================================================

                if (CPHA == 1'b0) begin

                    // Sample on leading edge
                    if (sample_edge) begin

                        rx_shreg <= {
                            rx_shreg[DATA_WIDTH-2:0],
                            miso
                        };

                        bit_cnt <= bit_cnt + 1'b1;

                        /*
                         * Last bit has just been sampled.
                         * We still need the trailing edge.
                         */
                        if (bit_cnt == DATA_WIDTH-1)
                            finish_pending <= 1'b1;

                    end

                    // Shift on trailing edge
                    if (shift_edge) begin

                        tx_shreg <= {
                            tx_shreg[DATA_WIDTH-2:0],
                            1'b0
                        };

                        if (bit_cnt < DATA_WIDTH-1)
                            mosi <= tx_shreg[DATA_WIDTH-2];
                        else
                            mosi <= 1'b0;

                    end

                end

                // ================================================
                // CPHA = 1
                // ================================================

                else begin

                    /*
                     * Shift/launch on leading edge.
                     */
                    if (shift_edge) begin

                        /*
                         * Present current MSB on MOSI.
                         */
                        mosi <= tx_shreg[DATA_WIDTH-1];

                        tx_shreg <= {
                            tx_shreg[DATA_WIDTH-2:0],
                            1'b0
                        };

                    end

                    /*
                     * Sample on trailing edge.
                     */
                    if (sample_edge) begin

                        rx_shreg <= {
                            rx_shreg[DATA_WIDTH-2:0],
                            miso
                        };

                        bit_cnt <= bit_cnt + 1'b1;

                    end

                end

            end

            // ----------------------------------------------------
            // Store received data
            // ----------------------------------------------------

            if (state == DEASSERT_CS)
                rx_data <= rx_shreg;

        end

    end

    // ============================================================
    // FSM next-state logic and control outputs
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
                 * CS remains asserted.
                 *
                 * start is intentionally ignored while busy.
                 */

                /*
                 * CPHA=0:
                 * Last bit was sampled on the leading edge.
                 * Wait for the following trailing edge.
                 */
                if ((CPHA == 1'b0) &&
                    spi_tick &&
                    shift_edge &&
                    finish_pending) begin

                    next_state = DEASSERT_CS;

                end

                /*
                 * CPHA=1:
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
    // Output control for CS and SCLK
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin
            cs_n <= 1'b1;
            sclk <= CPOL;
        end
        else begin

            case (state)

                IDLE: begin
                    cs_n <= 1'b1;
                    sclk <= CPOL;
                end

                ASSERT_CS: begin
                    cs_n <= 1'b0;
                    sclk <= CPOL;
                end

                SHIFT: begin
                    cs_n <= 1'b0;
                end

                DEASSERT_CS: begin
                    cs_n <= 1'b1;
                    sclk <= CPOL;
                end

                DONE: begin
                    cs_n <= 1'b1;
                    sclk <= CPOL;
                end

                default: begin
                    cs_n <= 1'b1;
                    sclk <= CPOL;
                end

            endcase

        end

    end

endmodule
