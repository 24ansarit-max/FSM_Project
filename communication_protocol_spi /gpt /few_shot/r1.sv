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
    // Counter widths
    // ============================================================

    localparam int DIV_WIDTH =
        (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);

    localparam int COUNT_WIDTH =
        (DATA_WIDTH <= 1) ? 1 : $clog2(DATA_WIDTH);

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
    // Registers
    // ============================================================

    logic [DATA_WIDTH-1:0] tx_shreg;
    logic [DATA_WIDTH-1:0] rx_shreg;

    logic [DIV_WIDTH-1:0]  clk_cnt;
    logic [COUNT_WIDTH-1:0] bit_cnt;

    // Used for CPHA=0 to wait for the final trailing edge
    logic finish_pending;

    // ============================================================
    // Clock divider tick
    // ============================================================

    logic spi_tick;

    assign spi_tick = (CLK_DIV <= 1) ||
                      (clk_cnt == CLK_DIV-1);

    // ============================================================
    // SPI edge definitions
    // ============================================================

    logic leading_edge;
    logic trailing_edge;
    logic sample_edge;
    logic shift_edge;

    /*
     * CPOL = 0:
     *     Leading  = rising
     *     Trailing = falling
     *
     * CPOL = 1:
     *     Leading  = falling
     *     Trailing = rising
     */

    assign leading_edge  = (sclk == CPOL);
    assign trailing_edge = (sclk != CPOL);

    /*
     * CPHA = 0:
     *     Sample on leading edge
     *     Shift on trailing edge
     *
     * CPHA = 1:
     *     Shift on leading edge
     *     Sample on trailing edge
     */

    assign sample_edge = (CPHA == 1'b0) ?
                         leading_edge : trailing_edge;

    assign shift_edge  = (CPHA == 1'b0) ?
                         trailing_edge : leading_edge;

    // ============================================================
    // Sequential logic
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state         <= IDLE;

            tx_shreg      <= '0;
            rx_shreg      <= '0;

            clk_cnt       <= '0;
            bit_cnt       <= '0;

            finish_pending <= 1'b0;

            sclk          <= CPOL;
            mosi          <= 1'b0;
            cs_n          <= 1'b1;

            rx_data       <= '0;

        end
        else begin

            state <= next_state;

            // ----------------------------------------------------
            // Default clock divider operation
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
            // Start new transaction
            // ----------------------------------------------------

            if (state == IDLE && start) begin

                tx_shreg <= tx_data;
                rx_shreg <= '0;

                bit_cnt <= '0;

                finish_pending <= 1'b0;

                /*
                 * First MSB is available before the first
                 * active SPI edge.
                 */
                mosi <= tx_data[DATA_WIDTH-1];

            end

            // ----------------------------------------------------
            // SPI transfer
            // ----------------------------------------------------

            if (state == SHIFT && spi_tick) begin

                // Toggle SPI clock
                sclk <= ~sclk;

                // -----------------------------------------------
                // Sample MISO
                // -----------------------------------------------

                if (sample_edge) begin

                    rx_shreg <= {
                        rx_shreg[DATA_WIDTH-2:0],
                        miso
                    };

                    bit_cnt <= bit_cnt + 1'b1;

                    /*
                     * For CPHA=0, the final sample occurs on the
                     * leading edge. One more trailing edge must
                     * occur before CS is released.
                     */
                    if ((CPHA == 1'b0) &&
                        (bit_cnt == DATA_WIDTH-1)) begin

                        finish_pending <= 1'b1;

                    end

                end

                // -----------------------------------------------
                // Shift MOSI
                // -----------------------------------------------

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

                // ------------------------------------------------
                // CPHA=0 final trailing edge
                // ------------------------------------------------

                if ((CPHA == 1'b0) &&
                    shift_edge &&
                    finish_pending) begin

                    finish_pending <= 1'b0;

                end

            end

            // ----------------------------------------------------
            // Save received data
            // ----------------------------------------------------

            if (state == DEASSERT_CS) begin
                rx_data <= rx_shreg;
            end

        end

    end

    // ============================================================
    // FSM next-state logic and outputs
    // ============================================================

    always_comb begin

        next_state = state;

        // Default outputs
        busy = 1'b0;
        done = 1'b0;

        case (state)

            // ----------------------------------------------------
            // IDLE
            // ----------------------------------------------------

            IDLE: begin

                busy = 1'b0;

                cs_n = 1'b1;
                sclk = CPOL;

                if (start)
                    next_state = ASSERT_CS;

            end

            // ----------------------------------------------------
            // ASSERT CS
            // ----------------------------------------------------

            ASSERT_CS: begin

                busy = 1'b1;

                cs_n = 1'b0;
                sclk = CPOL;

                next_state = SHIFT;

            end

            // ----------------------------------------------------
            // SHIFT
            // ----------------------------------------------------

            SHIFT: begin

                busy = 1'b1;
                cs_n = 1'b0;

                /*
                 * Start is ignored here.
                 *
                 * CPHA=1:
                 * final bit is sampled on trailing edge.
                 */
                if ((CPHA == 1'b1) &&
                    spi_tick &&
                    sample_edge &&
                    (bit_cnt == DATA_WIDTH-1)) begin

                    next_state = DEASSERT_CS;

                end

                /*
                 * CPHA=0:
                 * final bit is sampled on leading edge.
                 * Wait for the following trailing edge.
                 */
                else if ((CPHA == 1'b0) &&
                         spi_tick &&
                         shift_edge &&
                         finish_pending) begin

                    next_state = DEASSERT_CS;

                end

            end

            // ----------------------------------------------------
            // DEASSERT CS
            // ----------------------------------------------------

            DEASSERT_CS: begin

                busy = 1'b0;

                cs_n = 1'b1;
                sclk = CPOL;

                next_state = DONE;

            end

            // ----------------------------------------------------
            // DONE
            // ----------------------------------------------------

            DONE: begin

                busy = 1'b0;
                done = 1'b1;

                cs_n = 1'b1;
                sclk = CPOL;

                next_state = IDLE;

            end

            // ----------------------------------------------------
            // Default
            // ----------------------------------------------------

            default: begin

                next_state = IDLE;

                busy = 1'b0;
                done = 1'b0;

                cs_n = 1'b1;
                sclk = CPOL;

            end

        endcase

    end

endmodule
