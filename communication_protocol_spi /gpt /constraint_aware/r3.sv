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
    // Parameter checks
    // ============================================================

    initial begin
        if ((DATA_WIDTH != 8) &&
            (DATA_WIDTH != 16) &&
            (DATA_WIDTH != 32))
            $error("DATA_WIDTH must be 8, 16, or 32");

        if (CLK_DIV < 1)
            $error("CLK_DIV must be >= 1");
    end

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
    // MISO synchronizer
    // ============================================================

    (* ASYNC_REG = "TRUE" *) logic miso_sync_ff1;
    (* ASYNC_REG = "TRUE" *) logic miso_sync_ff2;

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
    // SPI datapath
    //
    // Separate TX/RX registers are required for correct full
    // duplex operation. A single register cannot retain the
    // remaining TX bits while simultaneously accumulating all
    // received bits.
    // ============================================================

    logic [DATA_WIDTH-1:0] tx_shift;
    logic [DATA_WIDTH-1:0] rx_shift;

    logic [BIT_CNT_WIDTH-1:0] bit_count;

    // Indicates that the final CPHA=0 sample has occurred.
    logic final_sampled;

    // ============================================================
    // Clock divider
    // ============================================================

    logic [DIV_WIDTH-1:0] clk_div_count;
    logic                  spi_tick;

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
            clk_div_count <= clk_div_count + DIV_WIDTH'(1);
        end
    end

    // ============================================================
    // SPI edge decoding
    //
    // Leading edge:
    //   CPOL=0 -> rising
    //   CPOL=1 -> falling
    //
    // Trailing edge:
    //   CPOL=0 -> falling
    //   CPOL=1 -> rising
    //
    // CPHA=0:
    //   sample on leading edge
    //   drive on trailing edge
    //
    // CPHA=1:
    //   drive on leading edge
    //   sample on trailing edge
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

                // CPHA=0 needs one additional trailing edge after
                // the final sampling edge.
                if ((CPHA == 1'b0) &&
                    final_sampled &&
                    spi_tick &&
                    drive_edge) begin

                    next_state = DEASSERT_CS;
                end

                // CPHA=1 finishes on the final sampling edge.
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
    // Shift-register datapath
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

            // ----------------------------------------------------
            // Start a new transaction
            // ----------------------------------------------------

            if ((state == IDLE) && start) begin

                tx_shift      <= tx_data;
                rx_shift      <= '0;
                bit_count     <= '0;
                final_sampled <= 1'b0;

                // CPHA=0 requires the first bit to be present
                // before the first leading sampling edge.
                if (CPHA == 1'b0)
                    mosi <= tx_data[DATA_WIDTH-1];
                else
                    mosi <= 1'b0;

            end

            // ----------------------------------------------------
            // SPI transfer
            // ----------------------------------------------------

            if ((state == SHIFT) && spi_tick) begin

                // =================================================
                // CPHA = 0
                //
                // Leading edge  -> sample MISO
                // Trailing edge -> change MOSI
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
                // Leading edge  -> drive MOSI
                // Trailing edge -> sample MISO
                // =================================================

                else begin

                    if (drive_edge) begin

                        // First leading edge sends the MSB.
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

            // ----------------------------------------------------
            // Transfer complete
            // ----------------------------------------------------

            if (state == DEASSERT_CS) begin
                rx_data <= rx_shift;
                mosi    <= 1'b0;
            end

        end
    end

    // ============================================================
    // Registered CS, BUSY and DONE
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            cs_n <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;

        end
        else begin

            // Default value makes DONE a one-clock pulse.
            done <= 1'b0;

            case (state)

                IDLE: begin
                    cs_n <= 1'b1;
                    busy <= 1'b0;
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
                    cs_n <= 1'b1;
                    busy <= 1'b0;
                end

                DONE: begin
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
