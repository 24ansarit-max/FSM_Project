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
    // Local parameters
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

    logic [DIV_WIDTH-1:0]  clk_count;
    logic [COUNT_WIDTH-1:0] bit_count;

    // ============================================================
    // SPI edge identification
    // ============================================================

    logic leading_edge;
    logic trailing_edge;
    logic sample_edge;
    logic shift_edge;

    /*
     * Leading edge:
     *   CPOL=0 : rising edge
     *   CPOL=1 : falling edge
     *
     * Trailing edge:
     *   CPOL=0 : falling edge
     *   CPOL=1 : rising edge
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
    // Main sequential FSM
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state         <= IDLE;

            sclk          <= CPOL;
            mosi          <= 1'b0;
            cs_n          <= 1'b1;

            rx_data       <= '0;

            tx_shift      <= '0;
            rx_shift      <= '0;

            clk_count     <= '0;
            bit_count     <= '0;

            busy          <= 1'b0;
            done          <= 1'b0;

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

                    /*
                     * Start is accepted only when the controller
                     * is idle.
                     *
                     * A start signal while BUSY is ignored.
                     */

                    if (start) begin

                        busy     <= 1'b1;

                        tx_shift <= tx_data;
                        rx_shift <= '0;

                        /*
                         * Put first MSB on MOSI before the first
                         * SPI sampling edge.
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
                     * Assert chip select.
                     */
                    cs_n <= 1'b0;

                    /*
                     * SCLK remains at its idle level.
                     */
                    sclk <= CPOL;

                    clk_count <= '0;

                    state <= SHIFT;

                end


                // =================================================
                // SHIFT
                // =================================================

                SHIFT: begin

                    busy <= 1'b1;
                    cs_n <= 1'b0;

                    /*
                     * Generate an SCLK transition every CLK_DIV
                     * system-clock cycles.
                     */
                    if ((CLK_DIV <= 1) ||
                        (clk_count == CLK_DIV-1)) begin

                        clk_count <= '0;

                        // =========================================
                        // SAMPLE MISO
                        // =========================================

                        if (sample_edge) begin

                            /*
                             * MSB-first receive shift register.
                             */
                            rx_shift <=
                                (rx_shift << 1) | miso;

                            bit_count <= bit_count + 1'b1;

                        end


                        // =========================================
                        // SHIFT MOSI
                        // =========================================

                        if (shift_edge) begin

                            /*
                             * Move the next transmit bit to MOSI.
                             */
                            tx_shift <= tx_shift << 1;

                            /*
                             * Only change MOSI when another data
                             * bit is available.
                             */
                            if (bit_count < DATA_WIDTH-1)
                                mosi <= tx_shift[DATA_WIDTH-2];
                            else
                                mosi <= 1'b0;

                        end


                        // =========================================
                        // Toggle SCLK
                        // =========================================

                        sclk <= ~sclk;


                        // =========================================
                        // End of transaction
                        // =========================================

                        if (CPHA == 1'b0) begin

                            /*
                             * CPHA=0:
                             *
                             * Final bit is sampled on the leading
                             * edge.
                             *
                             * We must still perform the trailing
                             * edge before CS is released.
                             */

                            if (shift_edge &&
                                bit_count == DATA_WIDTH) begin

                                state <= DEASSERT_CS;

                            end

                        end
                        else begin

                            /*
                             * CPHA=1:
                             *
                             * Final bit is sampled on the trailing
                             * edge.
                             *
                             * After this edge SCLK returns to its
                             * idle level, so CS can be released.
                             */

                            if (sample_edge &&
                                bit_count == DATA_WIDTH-1) begin

                                state <= DEASSERT_CS;

                            end

                        end

                    end
                    else begin

                        clk_count <= clk_count + 1'b1;

                    end

                end


                // =================================================
                // DEASSERT CS
                // =================================================

                DEASSERT_CS: begin

                    /*
                     * CS is released only after the complete SPI
                     * transaction.
                     */
                    cs_n <= 1'b1;

                    /*
                     * SCLK returns/stays at the CPOL idle level.
                     */
                    sclk <= CPOL;

                    busy <= 1'b0;

                    /*
                     * Store received data in output register.
                     */
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

                    /*
                     * One-clock completion pulse.
                     */
                    done <= 1'b1;

                    state <= IDLE;

                end


                // =================================================
                // Safety recovery
                // =================================================

                default: begin

                    state     <= IDLE;

                    sclk      <= CPOL;
                    cs_n      <= 1'b1;
                    mosi      <= 1'b0;

                    busy      <= 1'b0;
                    done      <= 1'b0;

                    clk_count <= '0;
                    bit_count <= '0;

                end

            endcase

        end

    end

endmodule
