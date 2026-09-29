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
    // Parameter-dependent widths
    // ============================================================

    localparam int unsigned DIV_WIDTH =
        (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);

    localparam int unsigned BIT_CNT_WIDTH =
        (DATA_WIDTH <= 1) ? 1 : $clog2(DATA_WIDTH);

    localparam logic [DIV_WIDTH-1:0] DIV_LAST =
        DIV_WIDTH'(CLK_DIV - 1);

    localparam logic [BIT_CNT_WIDTH-1:0] LAST_BIT =
        BIT_CNT_WIDTH'(DATA_WIDTH - 1);


    // ============================================================
    // FSM
    // ============================================================

    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        ASSERT_CS   = 3'b001,
        SHIFT       = 3'b010,
        DEASSERT_CS = 3'b011,
        DONE        = 3'b100
    } state_t;

    state_t state;
    state_t next_state;


    // ============================================================
    // TX/RX datapath
    // ============================================================

    logic [DATA_WIDTH-1:0] tx_shift;
    logic [DATA_WIDTH-1:0] rx_shift;

    logic [BIT_CNT_WIDTH-1:0] bit_count;

    logic final_sampled;


    // ============================================================
    // MISO synchronizer
    // ============================================================

    (* ASYNC_REG = "TRUE" *)
    logic miso_sync_ff1;

    (* ASYNC_REG = "TRUE" *)
    logic miso_sync_ff2;

    always_ff @(posedge clk) begin
        if (rst) begin
            miso_sync_ff1 <= 1'b0;
            miso_sync_ff2 <= 1'b0;
        end
        else begin
            miso_sync_ff1 <= miso;
            miso_sync_ff2 <= miso_sync_ff1;
        end
    end


    // ============================================================
    // Clock divider
    //
    // One spi_tick occurs every CLK_DIV system-clock cycles.
    // Each tick toggles SCLK.
    //
    // f_sclk = f_clk / (2 * CLK_DIV)
    // ============================================================

    logic [DIV_WIDTH-1:0] clk_div_count;
    logic                 spi_tick;

    always_comb begin

        spi_tick = 1'b0;

        if (CLK_DIV <= 1) begin
            spi_tick = 1'b1;
        end
        else if (clk_div_count == DIV_LAST) begin
            spi_tick = 1'b1;
        end
        else begin
            spi_tick = 1'b0;
        end

    end


    always_ff @(posedge clk) begin

        if (rst) begin
            clk_div_count <= '0;
        end
        else if (state != SHIFT) begin
            clk_div_count <= '0;
        end
        else if (spi_tick) begin
            clk_div_count <= '0;
        end
        else begin
            clk_div_count <=
                clk_div_count + DIV_WIDTH'(1);
        end

    end


    // ============================================================
    // SPI edge decoder
    //
    // Leading edge:
    //   CPOL=0 -> Rising
    //   CPOL=1 -> Falling
    //
    // Trailing edge:
    //   CPOL=0 -> Falling
    //   CPOL=1 -> Rising
    //
    // CPHA=0:
    //   Sample on leading
    //   Drive on trailing
    //
    // CPHA=1:
    //   Drive on leading
    //   Sample on trailing
    // ============================================================

    logic leading_edge;
    logic trailing_edge;
    logic sample_edge;
    logic drive_edge;

    always_comb begin

        leading_edge  = 1'b0;
        trailing_edge = 1'b0;
        sample_edge   = 1'b0;
        drive_edge    = 1'b0;

        leading_edge  = (sclk == CPOL);
        trailing_edge = (sclk != CPOL);

        if (CPHA == 1'b0) begin
            sample_edge = leading_edge;
            drive_edge  = trailing_edge;
        end
        else begin
            sample_edge = trailing_edge;
            drive_edge  = leading_edge;
        end

    end


    // ============================================================
    // Next-state logic
    // ============================================================

    always_comb begin

        next_state = state;

        case (state)

            IDLE: begin
                if (start)
                    next_state = ASSERT_CS;
            end


            ASSERT_CS: begin
                next_state = SHIFT;
            end


            SHIFT: begin

                // ------------------------------------------------
                // CPHA = 0
                // Final bit is sampled on leading edge.
                // The following trailing edge completes the
                // final clock period before CS is released.
                // ------------------------------------------------

                if ((CPHA == 1'b0) &&
                    final_sampled &&
                    spi_tick &&
                    drive_edge) begin

                    next_state = DEASSERT_CS;
                end

                // ------------------------------------------------
                // CPHA = 1
                // Final bit is sampled on trailing edge.
                // ------------------------------------------------

                else if ((CPHA == 1'b1) &&
                         spi_tick &&
                         sample_edge &&
                         (bit_count == LAST_BIT)) begin

                    next_state = DEASSERT_CS;
                end

            end


            DEASSERT_CS: begin
                next_state = DONE;
            end


            DONE: begin

                if (start)
                    next_state = ASSERT_CS;
                else
                    next_state = IDLE;

            end


            default: begin
                next_state = IDLE;
            end

        endcase

    end


    // ============================================================
    // State register
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst)
            state <= IDLE;
        else
            state <= next_state;

    end


    // ============================================================
    // SCLK generation
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            sclk <= CPOL;

        end
        else begin

            case (state)

                IDLE: begin
                    sclk <= CPOL;
                end

                ASSERT_CS: begin
                    sclk <= CPOL;
                end

                SHIFT: begin

                    if (spi_tick)
                        sclk <= ~sclk;

                end

                DEASSERT_CS: begin
                    sclk <= CPOL;
                end

                DONE: begin
                    sclk <= CPOL;
                end

                default: begin
                    sclk <= CPOL;
                end

            endcase

        end

    end


    // ============================================================
    // TX/RX shift-register datapath
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            tx_shift      <= '0;
            rx_shift      <= '0;
            bit_count     <= '0;
            final_sampled <= 1'b0;

            mosi          <= 1'b0;
            rx_data       <= '0;

        end
        else begin

            // ====================================================
            // Start a new transaction
            // ====================================================

            if ((state == IDLE) && start) begin

                tx_shift      <= tx_data;
                rx_shift      <= '0;
                bit_count     <= '0;
                final_sampled <= 1'b0;

                // CPHA=0:
                // First bit must already be available before
                // the first leading edge.
                if (CPHA == 1'b0)
                    mosi <= tx_data[DATA_WIDTH-1];
                else
                    mosi <= 1'b0;

            end


            // ====================================================
            // SPI transfer
            // ====================================================

            if ((state == SHIFT) && spi_tick) begin

                // =================================================
                // CPHA = 0
                //
                // Leading  edge -> sample MISO
                // Trailing edge -> drive next MOSI bit
                // =================================================

                if (CPHA == 1'b0) begin

                    if (sample_edge) begin

                        rx_shift <= {
                            rx_shift[DATA_WIDTH-2:0],
                            miso_sync_ff2
                        };

                        if (bit_count == LAST_BIT) begin

                            final_sampled <= 1'b1;

                        end
                        else begin

                            bit_count <=
                                bit_count + BIT_CNT_WIDTH'(1);

                        end

                    end


                    if (drive_edge) begin

                        tx_shift <= {
                            tx_shift[DATA_WIDTH-2:0],
                            1'b0
                        };

                        if (bit_count < LAST_BIT) begin
                            mosi <= tx_shift[DATA_WIDTH-2];
                        end
                        else begin
                            mosi <= 1'b0;
                        end

                    end

                end


                // =================================================
                // CPHA = 1
                //
                // Leading  edge -> drive MOSI
                // Trailing edge -> sample MISO
                // =================================================

                else begin

                    if (drive_edge) begin

                        mosi <= tx_shift[DATA_WIDTH-1];

                        tx_shift <= {
                            tx_shift[DATA_WIDTH-2:0],
                            1'b0
                        };

                    end


                    if (sample_edge) begin

                        rx_shift <= {
                            rx_shift[DATA_WIDTH-2:0],
                            miso_sync_ff2
                        };

                        if (bit_count != LAST_BIT) begin

                            bit_count <=
                                bit_count + BIT_CNT_WIDTH'(1);

                        end

                    end

                end

            end


            // ====================================================
            // Save received data
            // ====================================================

            if (state == DEASSERT_CS) begin

                rx_data <= rx_shift;
                mosi    <= 1'b0;

            end

        end

    end


    // ============================================================
    // Registered CS / BUSY / DONE
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            cs_n <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;

        end
        else begin

            // DONE is a one-clock pulse.
            done <= 1'b0;

            case (state)

                IDLE: begin

                    cs_n <= 1'b1;
                    busy <= 1'b0;

                    // Accept start.
                    if (start) begin
                        cs_n <= 1'b0;
                        busy <= 1'b1;
                    end

                end


                ASSERT_CS: begin

                    cs_n <= 1'b0;
                    busy <= 1'b1;

                end


                SHIFT: begin

                    cs_n <= 1'b0;
                    busy <= 1'b1;

                end


                DEASSERT_CS: begin

                    // Keep CS asserted during this state.
                    cs_n <= 1'b0;
                    busy <= 1'b1;

                end


                DONE: begin

                    // Release CS and generate one-cycle done.
                    cs_n <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;

                end


                default: begin

                    cs_n <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b0;

                end

            endcase

        end

    end

endmodule
