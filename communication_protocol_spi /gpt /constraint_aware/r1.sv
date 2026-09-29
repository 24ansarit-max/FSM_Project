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

    localparam logic [DIV_WIDTH-1:0] DIV_MAX =
        DIV_WIDTH'(CLK_DIV - 1);

    localparam logic [BIT_CNT_WIDTH-1:0] LAST_BIT =
        BIT_CNT_WIDTH'(DATA_WIDTH - 1);

    // ============================================================
    // FSM
    // ============================================================

    typedef enum logic [2:0] {
        IDLE       = 3'b000,
        ASSERT_CS  = 3'b001,
        SHIFT      = 3'b010,
        DEASSERT_CS= 3'b011,
        DONE       = 3'b100
    } state_t;

    state_t state;
    state_t next_state;

    // ============================================================
    // Datapath
    // Separate TX/RX registers are required for true full-duplex
    // operation because TX and RX shift in opposite directions.
    // ============================================================

    logic [DATA_WIDTH-1:0] tx_shift;
    logic [DATA_WIDTH-1:0] rx_shift;

    logic [BIT_CNT_WIDTH-1:0] bit_count;

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
        else if (clk_div_count == DIV_MAX) begin
            spi_tick = 1'b1;
        end
        else begin
            spi_tick = 1'b0;
        end
    end

    // ============================================================
    // MISO 2-flip-flop synchronizer
    // ============================================================

    (* ASYNC_REG = "TRUE" *) logic miso_sync1;
    (* ASYNC_REG = "TRUE" *) logic miso_sync2;

    always_ff @(posedge clk) begin
        if (rst) begin
            miso_sync1 <= 1'b0;
            miso_sync2 <= 1'b0;
        end
        else begin
            miso_sync1 <= miso;
            miso_sync2 <= miso_sync1;
        end
    end

    // ============================================================
    // SPI edge classification
    //
    // leading edge:
    //   CPOL=0 -> rising
    //   CPOL=1 -> falling
    //
    // trailing edge:
    //   CPOL=0 -> falling
    //   CPOL=1 -> rising
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
                if (start) begin
                    next_state = ASSERT_CS;
                end
            end

            ASSERT_CS: begin
                next_state = SHIFT;
            end

            SHIFT: begin

                if (spi_tick && sample_edge) begin

                    if (bit_count == LAST_BIT) begin
                        next_state = DEASSERT_CS;
                    end

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

        if (rst) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end

    end

    // ============================================================
    // SCLK divider
    // ============================================================

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
    // SPI datapath
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            tx_shift  <= '0;
            rx_shift  <= '0;
            bit_count <= '0;

            sclk      <= CPOL;
            mosi      <= 1'b0;
            rx_data   <= '0;

        end
        else begin

            // ----------------------------------------------------
            // Load transaction
            // ----------------------------------------------------

            if ((state == IDLE) && start) begin

                tx_shift  <= tx_data;
                rx_shift  <= '0;
                bit_count <= '0;

                /*
                 * First MSB is available before the first
                 * active sampling edge.
                 */
                mosi <= tx_data[DATA_WIDTH-1];

                sclk <= CPOL;

            end

            // ----------------------------------------------------
            // SPI clock and data transfer
            // ----------------------------------------------------

            if ((state == SHIFT) && spi_tick) begin

                // Generate next SPI edge.
                sclk <= ~sclk;

                // ------------------------------------------------
                // CPHA = 0
                //
                // Leading edge  : sample MISO
                // Trailing edge : change MOSI
                // ------------------------------------------------

                if (CPHA == 1'b0) begin

                    if (sample_edge) begin

                        rx_shift <= {
                            rx_shift[DATA_WIDTH-2:0],
                            miso_sync2
                        };

                        bit_count <= bit_count + BIT_CNT_WIDTH'(1);

                    end

                    if (drive_edge) begin

                        tx_shift <= {
                            tx_shift[DATA_WIDTH-2:0],
                            1'b0
                        };

                        mosi <= tx_shift[DATA_WIDTH-2];

                    end

                end

                // ------------------------------------------------
                // CPHA = 1
                //
                // Leading edge  : change MOSI
                // Trailing edge : sample MISO
                // ------------------------------------------------

                else begin

                    if (drive_edge) begin

                        tx_shift <= {
                            tx_shift[DATA_WIDTH-2:0],
                            1'b0
                        };

                        mosi <= tx_shift[DATA_WIDTH-2];

                    end

                    if (sample_edge) begin

                        rx_shift <= {
                            rx_shift[DATA_WIDTH-2:0],
                            miso_sync2
                        };

                        bit_count <= bit_count + BIT_CNT_WIDTH'(1);

                    end

                end

            end

            // ----------------------------------------------------
            // Capture final received word
            // ----------------------------------------------------

            if (state == DEASSERT_CS) begin

                rx_data <= rx_shift;

            end

        end

    end

    // ============================================================
    // Registered CS, BUSY and DONE outputs
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            cs_n <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
        end
        else begin

            // DONE is a one-cycle pulse.
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
