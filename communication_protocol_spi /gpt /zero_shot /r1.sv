module spi_master #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned CLK_DIV    = 4,
    parameter bit          CPOL       = 1'b0,
    parameter bit          CPHA       = 1'b0
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
    // Parameters / local constants
    // ============================================================

    localparam int DIV_WIDTH =
        (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);

    localparam int COUNT_WIDTH =
        (DATA_WIDTH <= 1) ? 1 : $clog2(DATA_WIDTH + 1);

    // ============================================================
    // FSM states
    // ============================================================

    typedef enum logic [2:0] {
        IDLE,
        ASSERT_CS,
        SHIFT,
        DEASSERT_CS,
        DONE
    } state_t;

    state_t state;

    // ============================================================
    // Internal registers
    // ============================================================

    logic [DATA_WIDTH-1:0] tx_shift;
    logic [DATA_WIDTH-1:0] rx_shift;

    logic [DIV_WIDTH-1:0] clk_count;

    // Number of bits already sampled
    logic [COUNT_WIDTH-1:0] bit_count;

    // ============================================================
    // SPI edge definitions
    // ============================================================

    logic leading_edge;
    logic trailing_edge;
    logic sample_edge;
    logic shift_edge;

    /*
     * Before toggling SCLK:
     *
     * CPOL = 0:
     *   SCLK = 0 -> 1 : leading edge
     *   SCLK = 1 -> 0 : trailing edge
     *
     * CPOL = 1:
     *   SCLK = 1 -> 0 : leading edge
     *   SCLK = 0 -> 1 : trailing edge
     */

    always_comb begin

        if (sclk == CPOL) begin
            leading_edge  = 1'b1;
            trailing_edge = 1'b0;
        end
        else begin
            leading_edge  = 1'b0;
            trailing_edge = 1'b1;
        end

        // CPHA = 0 -> sample leading, shift trailing
        // CPHA = 1 -> shift leading, sample trailing

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
    // Main FSM / datapath
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state     <= IDLE;

            sclk      <= CPOL;
            mosi      <= 1'b0;
            cs_n      <= 1'b1;

            rx_data   <= '0;

            tx_shift  <= '0;
            rx_shift  <= '0;

            clk_count <= '0;
            bit_count <= '0;

            busy      <= 1'b0;
            done      <= 1'b0;

        end
        else begin

            // done is a one-clock pulse
            done <= 1'b0;

            case (state)

                // =================================================
                // IDLE
                // =================================================

                IDLE: begin

                    busy      <= 1'b0;
                    cs_n      <= 1'b1;
                    sclk      <= CPOL;
                    clk_count <= '0;
                    bit_count <= '0;

                    if (start) begin

                        busy     <= 1'b1;

                        tx_shift <= tx_data;
                        rx_shift <= '0;

                        /*
                         * First transmitted bit must already be
                         * available before the first sampling edge
                         * for CPHA = 0.
                         *
                         * We also place MSB on MOSI for CPHA = 1.
                         * The first active edge will then be the
                         * shifting edge.
                         */

                        mosi <= tx_data[DATA_WIDTH-1];

                        state <= ASSERT_CS;
                    end

                end


                // =================================================
                // ASSERT CS
                // =================================================

                ASSERT_CS: begin

                    /*
                     * CS is asserted here and remains asserted
                     * throughout the complete transaction.
                     */

                    cs_n      <= 1'b0;
                    sclk      <= CPOL;
                    clk_count <= '0;

                    state <= SHIFT;

                end


                // =================================================
                // SHIFT
                // =================================================

                SHIFT: begin

                    cs_n <= 1'b0;
                    busy <= 1'b1;

                    /*
                     * Generate one SPI clock transition every
                     * CLK_DIV system-clock cycles.
                     */

                    if (CLK_DIV <= 1) begin

                        clk_count <= '0;

                        // -----------------------------------------
                        // Sampling edge
                        // -----------------------------------------

                        if (sample_edge) begin

                            rx_shift <= {
                                rx_shift[DATA_WIDTH-2:0],
                                miso
                            };

                            bit_count <= bit_count + 1'b1;

                            /*
                             * For CPHA = 0 the final sample happens
                             * on the leading edge.
                             *
                             * We cannot immediately deassert CS
                             * because the clock must return to its
                             * idle level. Therefore the final
                             * trailing edge is allowed to occur.
                             */

                        end


                        // -----------------------------------------
                        // Shift edge
                        // -----------------------------------------

                        if (shift_edge) begin

                            tx_shift <= {
                                tx_shift[DATA_WIDTH-2:0],
                                1'b0
                            };

                            /*
                             * Present next MSB on MOSI.
                             */

                            if (bit_count < DATA_WIDTH)
                                mosi <= tx_shift[DATA_WIDTH-2];
                            else
                                mosi <= 1'b0;

                        end


                        // -----------------------------------------
                        // Toggle SCLK
                        // -----------------------------------------

                        sclk <= ~sclk;


                        /*
                         * Transaction completion:
                         *
                         * CPHA = 0:
                         * final bit is sampled on leading edge.
                         * Wait for trailing edge before CS release.
                         *
                         * CPHA = 1:
                         * final bit is sampled on trailing edge,
                         * so the transaction can finish immediately
                         * after that sampling edge.
                         */

                        if (CPHA == 1'b0) begin

                            if (sample_edge &&
                                bit_count == DATA_WIDTH-1) begin

                                // Do not finish until next edge
                                // brings SCLK back to idle.

                            end

                            if (shift_edge &&
                                bit_count == DATA_WIDTH) begin

                                state <= DEASSERT_CS;

                            end

                        end
                        else begin

                            if (sample_edge &&
                                bit_count == DATA_WIDTH) begin

                                state <= DEASSERT_CS;

                            end

                        end

                    end
                    else begin

                        // =========================================
                        // Normal CLK_DIV operation
                        // =========================================

                        if (clk_count == CLK_DIV-1) begin

                            clk_count <= '0;

                            // -------------------------------------
                            // Sampling edge
                            // -------------------------------------

                            if (sample_edge) begin

                                rx_shift <= {
                                    rx_shift[DATA_WIDTH-2:0],
                                    miso
                                };

                                bit_count <= bit_count + 1'b1;

                            end


                            // -------------------------------------
                            // Shift edge
                            // -------------------------------------

                            if (shift_edge) begin

                                tx_shift <= {
                                    tx_shift[DATA_WIDTH-2:0],
                                    1'b0
                                };

                                if (bit_count < DATA_WIDTH)
                                    mosi <= tx_shift[DATA_WIDTH-2];
                                else
                                    mosi <= 1'b0;

                            end


                            // -------------------------------------
                            // Toggle SPI clock
                            // -------------------------------------

                            sclk <= ~sclk;


                            // -------------------------------------
                            // Completion
                            // -------------------------------------

                            if (CPHA == 1'b0) begin

                                /*
                                 * CPHA=0:
                                 * sampling occurs on leading edge.
                                 * Final shift edge completes the
                                 * clock cycle.
                                 */

                                if (shift_edge &&
                                    bit_count == DATA_WIDTH) begin

                                    state <= DEASSERT_CS;

                                end

                            end
                            else begin

                                /*
                                 * CPHA=1:
                                 * sampling occurs on trailing edge.
                                 */

                                if (sample_edge &&
                                    bit_count == DATA_WIDTH) begin

                                    state <= DEASSERT_CS;

                                end

                            end

                        end
                        else begin

                            clk_count <= clk_count + 1'b1;

                        end

                    end

                end


                // =================================================
                // DEASSERT CS
                // =================================================

                DEASSERT_CS: begin

                    /*
                     * SCLK is already returned to its idle level
                     * after the final edge.
                     */

                    cs_n <= 1'b1;
                    busy <= 1'b0;

                    rx_data <= rx_shift;

                    state <= DONE;

                end


                // =================================================
                // DONE
                // =================================================

                DONE: begin

                    cs_n <= 1'b1;
                    sclk <= CPOL;
                    busy <= 1'b0;

                    done <= 1'b1;

                    state <= IDLE;

                end


                // =================================================
                // Default recovery
                // =================================================

                default: begin

                    state     <= IDLE;
                    cs_n      <= 1'b1;
                    sclk      <= CPOL;
                    mosi      <= 1'b0;
                    busy      <= 1'b0;
                    clk_count <= '0;
                    bit_count <= '0;

                end

            endcase

        end

    end

endmodule
