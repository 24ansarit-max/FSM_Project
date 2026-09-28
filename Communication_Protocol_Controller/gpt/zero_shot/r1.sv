`timescale 1ns/1ps

module parameterized_uart #(
    parameter int unsigned CLK_FREQ_HZ = 50_000_000,
    parameter int unsigned BAUD_RATE   = 115_200,
    parameter int unsigned DATA_BITS   = 8,   // 7 or 8
    parameter int unsigned PARITY_MODE = 0,   // 0=None, 1=Even, 2=Odd
    parameter int unsigned STOP_BITS   = 1    // 1 or 2
)(
    input  logic                  clk,
    input  logic                  rst,

    // Transmitter
    input  logic                  tx_start,
    input  logic [DATA_BITS-1:0]  tx_data,

    // Receiver
    input  logic                  rx_serial_in,

    // Outputs
    output logic                  tx_serial_out,
    output logic                  tx_busy,
    output logic                  tx_done,

    output logic [DATA_BITS-1:0]  rx_data,
    output logic                  rx_valid,

    output logic                  framing_error,
    output logic                  parity_error,
    output logic                  overrun_error
);

    // ============================================================
    // BAUD RATE GENERATOR
    // ============================================================

    localparam int unsigned BAUD_DIV =
        (CLK_FREQ_HZ / BAUD_RATE);

    localparam int unsigned HALF_BAUD_DIV =
        (BAUD_DIV / 2);

    localparam int unsigned BAUD_CNT_WIDTH =
        (BAUD_DIV <= 1) ? 1 : $clog2(BAUD_DIV);

    logic [BAUD_CNT_WIDTH-1:0] baud_cnt;
    logic baud_tick;

    always_ff @(posedge clk) begin
        if (rst) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b0;
        end
        else begin
            baud_tick <= 1'b0;

            if (baud_cnt >= BAUD_DIV-1) begin
                baud_cnt  <= '0;
                baud_tick <= 1'b1;
            end
            else begin
                baud_cnt <= baud_cnt + 1'b1;
            end
        end
    end

    // ============================================================
    // RX INPUT SYNCHRONIZER
    // ============================================================

    logic rx_sync1;
    logic rx_sync2;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end
        else begin
            rx_sync1 <= rx_serial_in;
            rx_sync2 <= rx_sync1;
        end
    end

    // ============================================================
    // TRANSMITTER FSM
    // ============================================================

    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP,
        TX_DONE
    } tx_state_t;

    tx_state_t tx_state;

    logic [DATA_BITS-1:0] tx_shift;
    logic [DATA_BITS-1:0] tx_data_latched;

    logic [$clog2(DATA_BITS+1)-1:0] tx_bit_count;
    logic [$clog2(STOP_BITS+1)-1:0] tx_stop_count;

    logic tx_parity;

    // ------------------------------------------------------------
    // TX parity calculation
    // ------------------------------------------------------------

    always_comb begin
        case (PARITY_MODE)
            1: tx_parity = ^tx_shift;       // Even parity
            2: tx_parity = ~(^tx_shift);    // Odd parity
            default: tx_parity = 1'b0;
        endcase
    end

    // ------------------------------------------------------------
    // TX FSM
    // ------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            tx_state        <= TX_IDLE;
            tx_serial_out   <= 1'b1;
            tx_busy         <= 1'b0;
            tx_done         <= 1'b0;

            tx_shift        <= '0;
            tx_data_latched <= '0;
            tx_bit_count    <= '0;
            tx_stop_count   <= '0;
        end
        else begin

            // tx_done is a one-clock pulse
            tx_done <= 1'b0;

            case (tx_state)

                // ------------------------------------------------
                // IDLE
                // ------------------------------------------------
                TX_IDLE: begin
                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;

                    if (tx_start) begin
                        tx_data_latched <= tx_data;
                        tx_shift        <= tx_data;

                        tx_bit_count  <= '0;
                        tx_stop_count <= '0;

                        tx_busy       <= 1'b1;
                        tx_state      <= TX_START;
                    end
                end

                // ------------------------------------------------
                // START BIT
                // ------------------------------------------------
                TX_START: begin
                    tx_serial_out <= 1'b0;

                    if (baud_tick) begin
                        tx_state <= TX_DATA;
                    end
                end

                // ------------------------------------------------
                // DATA BITS
                // ------------------------------------------------
                TX_DATA: begin
                    tx_serial_out <= tx_shift[0];

                    if (baud_tick) begin

                        if (tx_bit_count == DATA_BITS-1) begin
                            tx_bit_count <= '0;

                            if (PARITY_MODE != 0)
                                tx_state <= TX_PARITY;
                            else
                                tx_state <= TX_STOP;
                        end
                        else begin
                            tx_bit_count <= tx_bit_count + 1'b1;
                            tx_shift     <= tx_shift >> 1;
                        end
                    end
                end

                // ------------------------------------------------
                // PARITY
                // ------------------------------------------------
                TX_PARITY: begin
                    tx_serial_out <= tx_parity;

                    if (baud_tick) begin
                        tx_stop_count <= '0;
                        tx_state      <= TX_STOP;
                    end
                end

                // ------------------------------------------------
                // STOP BITS
                // ------------------------------------------------
                TX_STOP: begin
                    tx_serial_out <= 1'b1;

                    if (baud_tick) begin

                        if (tx_stop_count == STOP_BITS-1) begin
                            tx_state <= TX_DONE;
                        end
                        else begin
                            tx_stop_count <= tx_stop_count + 1'b1;
                        end
                    end
                end

                // ------------------------------------------------
                // DONE
                // ------------------------------------------------
                TX_DONE: begin
                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;
                    tx_done       <= 1'b1;

                    tx_state <= TX_IDLE;
                end

                default: begin
                    tx_state      <= TX_IDLE;
                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;
                end

            endcase
        end
    end

    // ============================================================
    // RECEIVER FSM
    // ============================================================

    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START_DETECT,
        RX_DATA,
        RX_PARITY,
        RX_STOP,
        RX_ERROR_DONE
    } rx_state_t;

    rx_state_t rx_state;

    logic [DATA_BITS-1:0] rx_shift;

    logic [$clog2(DATA_BITS+1)-1:0] rx_bit_count;
    logic [$clog2(STOP_BITS+1)-1:0] rx_stop_count;

    logic [BAUD_CNT_WIDTH-1:0] rx_sample_count;

    logic rx_parity;
    logic rx_frame_error;

    // ============================================================
    // RX SAMPLE TIMER
    // ============================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_sample_count <= '0;
        end
        else begin

            case (rx_state)

                RX_START_DETECT: begin
                    if (rx_sample_count < HALF_BAUD_DIV)
                        rx_sample_count <= rx_sample_count + 1'b1;
                end

                RX_DATA,
                RX_PARITY,
                RX_STOP: begin
                    if (rx_sample_count >= BAUD_DIV-1)
                        rx_sample_count <= '0;
                    else
                        rx_sample_count <= rx_sample_count + 1'b1;
                end

                default: begin
                    rx_sample_count <= '0;
                end

            endcase
        end
    end

    // ============================================================
    // RX PARITY CALCULATION
    // ============================================================

    always_comb begin
        case (PARITY_MODE)

            1: rx_parity = ^rx_shift;        // Even parity
            2: rx_parity = ~(^rx_shift);     // Odd parity
            default: rx_parity = 1'b0;

        endcase
    end

    // ============================================================
    // RECEIVER FSM
    // ============================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_state       <= RX_IDLE;

            rx_data        <= '0;
            rx_shift       <= '0;

            rx_valid       <= 1'b0;

            framing_error  <= 1'b0;
            parity_error   <= 1'b0;
            overrun_error  <= 1'b0;

            rx_bit_count   <= '0;
            rx_stop_count  <= '0;

            rx_frame_error <= 1'b0;
        end
        else begin

            // Default: pulse-style status outputs
            rx_valid      <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
            overrun_error <= 1'b0;

            case (rx_state)

                // ------------------------------------------------
                // IDLE
                // ------------------------------------------------
                RX_IDLE: begin

                    rx_bit_count   <= '0;
                    rx_stop_count  <= '0;
                    rx_frame_error <= 1'b0;

                    // UART idle line = HIGH
                    // LOW indicates possible start bit
                    if (rx_sync2 == 1'b0) begin
                        rx_sample_count <= '0;
                        rx_state <= RX_START_DETECT;
                    end
                end

                // ------------------------------------------------
                // START DETECT
                // ------------------------------------------------
                // Wait half a bit and verify that line is still LOW.
                // This rejects short glitches.
                // ------------------------------------------------
                RX_START_DETECT: begin

                    if (rx_sample_count >= HALF_BAUD_DIV-1) begin

                        rx_sample_count <= '0;

                        if (rx_sync2 == 1'b0) begin
                            // Valid start bit
                            rx_shift       <= '0;
                            rx_bit_count   <= '0;
                            rx_stop_count  <= '0;
                            rx_frame_error <= 1'b0;

                            rx_state <= RX_DATA;
                        end
                        else begin
                            // False start / glitch
                            rx_state <= RX_IDLE;
                        end
                    end
                end

                // ------------------------------------------------
                // DATA
                // ------------------------------------------------
                RX_DATA: begin

                    // Sample near center of every data bit
                    if (rx_sample_count >= BAUD_DIV-1) begin

                        rx_sample_count <= '0;

                        rx_shift[rx_bit_count] <= rx_sync2;

                        if (rx_bit_count == DATA_BITS-1) begin

                            rx_bit_count <= '0;

                            if (PARITY_MODE != 0)
                                rx_state <= RX_PARITY;
                            else
                                rx_state <= RX_STOP;

                        end
                        else begin
                            rx_bit_count <= rx_bit_count + 1'b1;
                        end
                    end
                end

                // ------------------------------------------------
                // PARITY
                // ------------------------------------------------
                RX_PARITY: begin

                    if (rx_sample_count >= BAUD_DIV-1) begin

                        rx_sample_count <= '0;

                        if (rx_sync2 != rx_parity)
                            parity_error <= 1'b1;

                        rx_state <= RX_STOP;
                        rx_stop_count <= '0;
                    end
                end

                // ------------------------------------------------
                // STOP
                // ------------------------------------------------
                RX_STOP: begin

                    if (rx_sample_count >= BAUD_DIV-1) begin

                        rx_sample_count <= '0;

                        // Stop bit must be HIGH
                        if (rx_sync2 == 1'b0) begin
                            rx_frame_error <= 1'b1;
                            framing_error  <= 1'b1;
                        end

                        if (rx_stop_count == STOP_BITS-1) begin

                            // Complete received byte
                            rx_data <= rx_shift;

                            // Overrun indication:
                            // rx_valid is pulsed for one clock.
                            // A new byte completed while it was already
                            // asserted is considered an overrun.
                            if (rx_valid)
                                overrun_error <= 1'b1;

                            rx_valid <= 1'b1;

                            rx_state <= RX_ERROR_DONE;

                        end
                        else begin
                            rx_stop_count <= rx_stop_count + 1'b1;
                        end
                    end
                end

                // ------------------------------------------------
                // ERROR / DONE
                // ------------------------------------------------
                RX_ERROR_DONE: begin

                    rx_state <= RX_IDLE;
                end

                default: begin
                    rx_state <= RX_IDLE;
                end

            endcase
        end
    end

endmodule
