module spi_master #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned CLK_DIV    = 4,
    parameter bit          CPOL       = 1'b0,
    parameter bit          CPHA       = 1'b0
)(
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   start,
    input  logic [DATA_WIDTH-1:0]  tx_data,
    input  logic                   miso,

    output logic                   sclk,
    output logic                   mosi,
    output logic                   cs_n,
    output logic [DATA_WIDTH-1:0]  rx_data,
    output logic                   busy,
    output logic                   done
);

    // ============================================================
    // Parameter checks
    // ============================================================

    initial begin
        if (DATA_WIDTH != 8 &&
            DATA_WIDTH != 16 &&
            DATA_WIDTH != 32)
            $error("DATA_WIDTH must be 8, 16, or 32");

        if (CLK_DIV < 1)
            $error("CLK_DIV must be >= 1");
    end

    // ============================================================
    // Counter widths
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
    // Datapath
    // ============================================================

    logic [DATA_WIDTH-1:0] tx_shreg;
    logic [DATA_WIDTH-1:0] rx_shreg;

    logic [DIV_WIDTH-1:0]  clk_cnt;
    logic [COUNT_WIDTH-1:0] bit_cnt;

    /*
     * Used for CPHA=0.
     *
     * The final bit is sampled on the leading edge, but the
     * following trailing edge must still occur before CS is
     * released.
     */
    logic finish_pending;

    // ============================================================
    // SPI clock divider
    // ============================================================

    logic spi_tick;

    always_comb begin

        if (CLK_DIV <= 1)
            spi_tick = 1'b1;
        else if (clk_cnt == CLK_DIV-1)
            spi_tick = 1'b1;
        else
            spi_tick = 1'b0;

    end

    // ============================================================
    // SPI edge detection
    // ============================================================

    logic leading_edge;
    logic trailing_edge;
    logic sample_edge;
    logic shift_edge;

    always_comb begin

        /*
         * CPOL = 0:
         *   leading  = rising
         *   trailing = falling
         *
         * CPOL = 1:
         *   leading  = falling
         *   trailing = rising
         */

        leading_edge  = (sclk == CPOL);
        trailing_edge = (sclk != CPOL);

        /*
         * CPHA = 0:
         *   sample on leading
         *   shift on trailing
         *
         * CPHA = 1:
         *   shift on leading
         *   sample on trailing
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
    // Sequential datapath
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
            rx_data        <= '0;

        end
        else begin

            // ----------------------------------------------------
            // FSM state register
            // ----------------------------------------------------

            state <= next_state;

            // ----------------------------------------------------
            // Clock divider
            // ----------------------------------------------------

            if (state != SHIFT) begin

                clk_cnt <= '0;

            end
            else if (spi_tick) begin

                clk_cnt <= '0;

            end
            else begin

                clk_cnt <= clk_cnt + 1'b1;

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
                 * First MSB is placed on MOSI before the first
                 * sampling edge.
                 *
                 * This is required for CPHA=0 and is also a
                 * convenient initial value for CPHA=1.
                 */
                mosi <= tx_data[DATA_WIDTH-1];

            end

            // ----------------------------------------------------
            // SPI SHIFT state
            // ----------------------------------------------------

            if (state == SHIFT && spi_tick) begin

                // Toggle SCLK
                sclk <= ~sclk;

                // =================================================
                // CPHA = 0
                // =================================================

                if (CPHA == 1'b0) begin

                    // ---------------------------------------------
                    // Sample MISO on leading edge
                    // ---------------------------------------------

                    if (sample_edge) begin

                        rx_shreg <= {
                            rx_shreg[DATA_WIDTH-2:0],
                            miso
                        };

                        bit_cnt <= bit_cnt + 1'b1;

                        /*
                         * Final bit has been sampled.
                         * We still need the trailing edge.
                         */
                        if (bit_cnt == DATA_WIDTH-1)
                            finish_pending <= 1'b1;

                    end

                    // ---------------------------------------------
                    // Shift MOSI on trailing edge
                    // ---------------------------------------------

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

                // =================================================
                // CPHA = 1
                // =================================================

                else begin

                    // ---------------------------------------------
                    // Drive MOSI on leading edge
                    // ---------------------------------------------

                    if (shift_edge) begin

                        /*
                         * Present current MSB.
                         */
                        mosi <= tx_shreg[DATA_WIDTH-1];

                        tx_shreg <= {
                            tx_shreg[DATA_WIDTH-2:0],
                            1'b0
                        };

                    end

                    // ---------------------------------------------
                    // Sample MISO on trailing edge
                    // ---------------------------------------------

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
            // Finalize received data
            // ----------------------------------------------------

            if (state == DEASSERT_CS) begin

                rx_data <= rx_shreg;

            end

        end

    end

    // ============================================================
    // FSM next-state logic
    // ============================================================

    always_comb begin

        next_state = state;

        case (state)

            // ====================================================
            // IDLE
            // ====================================================

            IDLE: begin

                if (start)
                    next_state = ASSERT_CS;

            end

            // ====================================================
            // ASSERT CS
            // ====================================================

            ASSERT_CS: begin

                next_state = SHIFT;

            end

            // ====================================================
            // SHIFT
            // ====================================================

            SHIFT: begin

                /*
                 * CPHA=0:
                 *
                 * Final bit is sampled on leading edge.
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
                 *
                 * Final bit is sampled on trailing edge.
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

                next_state = DONE;

            end

            // ====================================================
            // DONE
            // ====================================================

            DONE: begin

                next_state = IDLE;

            end

            // ====================================================
            // Recovery
            // ====================================================

            default: begin

                next_state = IDLE;

            end

        endcase

    end

    // ============================================================
    // Output control
    // ============================================================

    always_comb begin

        /*
         * Default outputs
         */
        busy = 1'b0;
        done = 1'b0;

        cs_n = 1'b1;

        case (state)

            // ----------------------------------------------------
            // IDLE
            // ----------------------------------------------------

            IDLE: begin

                busy = 1'b0;
                cs_n = 1'b1;

            end

            // ----------------------------------------------------
            // ASSERT CS
            // ----------------------------------------------------

            ASSERT_CS: begin

                busy = 1'b1;
                cs_n = 1'b0;

            end

            // ----------------------------------------------------
            // SHIFT
            // ----------------------------------------------------

            SHIFT: begin

                busy = 1'b1;
                cs_n = 1'b0;

            end

            // ----------------------------------------------------
            // DEASSERT CS
            // ----------------------------------------------------

            DEASSERT_CS: begin

                busy = 1'b0;
                cs_n = 1'b1;

            end

            // ----------------------------------------------------
            // DONE
            // ----------------------------------------------------

            DONE: begin

                busy = 1'b0;
                done = 1'b1;
                cs_n = 1'b1;

            end

            default: begin

                busy = 1'b0;
                done = 1'b0;
                cs_n = 1'b1;

            end

        endcase

    end

endmodule
