`timescale 1ns/1ps

module parameterized_uart #(
    parameter int unsigned CLK_FREQ_HZ = 50_000_000,
    parameter int unsigned BAUD_RATE   = 115_200,
    parameter int unsigned DATA_BITS   = 8,       // 7 or 8
    parameter int unsigned PARITY_MODE = 0,       // 0=None, 1=Even, 2=Odd
    parameter int unsigned STOP_BITS   = 1        // 1 or 2
)(
    input  logic                 clk,
    input  logic                 rst,

    // ---------------- TRANSMITTER ----------------
    input  logic                 tx_start,
    input  logic [DATA_BITS-1:0] tx_data,

    output logic                 tx_serial_out,
    output logic                 tx_busy,
    output logic                 tx_done,

    // ---------------- RECEIVER ----------------
    input  logic                 rx_serial_in,

    output logic [DATA_BITS-1:0] rx_data,
    output logic                 rx_valid,
    output logic                 framing_error,
    output logic                 parity_error,
    output logic                 overrun_error
);

    // ============================================================
    // PARAMETER CHECKS
    // ============================================================

    initial begin
        if ((DATA_BITS != 7) && (DATA_BITS != 8))
            $error("DATA_BITS must be 7 or 8");

        if (PARITY_MODE > 2)
            $error("PARITY_MODE: 0=None, 1=Even, 2=Odd");

        if ((STOP_BITS != 1) && (STOP_BITS != 2))
            $error("STOP_BITS must be 1 or 2");

        if (BAUD_RATE == 0)
            $error("BAUD_RATE must be greater than zero");

        if (CLK_FREQ_HZ < BAUD_RATE)
            $error("CLK_FREQ_HZ should normally be >= BAUD_RATE");
    end

    // ============================================================
    // BAUD RATE PARAMETERS
    // ============================================================

    // Number of system-clock cycles in one UART bit.
    localparam int unsigned BAUD_DIV =
        (CLK_FREQ_HZ / BAUD_RATE);

    localparam int unsigned HALF_BAUD_DIV =
        (BAUD_DIV / 2);

    localparam int unsigned BAUD_CNT_WIDTH =
        (BAUD_DIV <= 1) ? 1 : $clog2(BAUD_DIV);

    localparam int unsigned DATA_CNT_WIDTH =
        (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);

    localparam int unsigned STOP_CNT_WIDTH =
        (STOP_BITS <= 1) ? 1 : $clog2(STOP_BITS);

    // ============================================================
    // COMMON BAUD TICK GENERATOR
    // ============================================================

    logic [BAUD_CNT_WIDTH-1:0] baud_counter;
    logic baud_tick;

    always_ff @(posedge clk) begin
        if (rst) begin
            baud_counter <= '0;
            baud_tick    <= 1'b0;
        end
        else begin
            baud_tick <= 1'b0;

            if (baud_counter >= BAUD_DIV-1) begin
                baud_counter <= '0;
                baud_tick    <= 1'b1;
            end
            else begin
                baud_counter <= baud_counter + 1'b1;
            end
        end
    end

    // ============================================================
    // RX INPUT SYNCHRONIZER
    // ============================================================

    logic rx_meta;
    logic rx_sync;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end
        else begin
            rx_meta <= rx_serial_in;
            rx_sync <= rx_meta;
        end
    end

    // UART line is HIGH when idle.
    // ============================================================
    //                    TRANSMITTER
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
    logic                 tx_parity_bit;

    logic [DATA_CNT_WIDTH-1:0] tx_bit_count;
    logic [STOP_CNT_WIDTH-1:0] tx_stop_count;

    // ------------------------------------------------------------
    // TX parity
    // ------------------------------------------------------------

    always_comb begin
        case (PARITY_MODE)
            1: tx_parity_bit = ^tx_shift;        // EVEN
            2: tx_parity_bit = ~(^tx_shift);     // ODD
            default: tx_parity_bit = 1'b0;       // NONE
        endcase
    end

    // ------------------------------------------------------------
    // TX FSM
    // ------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            tx_state      <= TX_IDLE;

            tx_serial_out <= 1'b1;
            tx_busy       <= 1'b0;
            tx_done       <= 1'b0;

            tx_shift      <= '0;
            tx_bit_count  <= '0;
            tx_stop_count <= '0;
        end
        else begin

            // tx_done is a one-clock pulse.
            tx_done <= 1'b0;

            case (tx_state)

                // =================================================
                // IDLE
                // =================================================
                TX_IDLE: begin
                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;

                    if (tx_start) begin
                        // Latch data.
                        tx_shift      <= tx_data;
                        tx_bit_count  <= '0;
                        tx_stop_count <= '0;

                        tx_busy  <= 1'b1;
                        tx_state <= TX_START;
                    end
                end

                // =================================================
                // START BIT
                // =================================================
                TX_START: begin
                    // UART START = LOW
                    tx_serial_out <= 1'b0;

                    if (baud_tick) begin
                        tx_state <= TX_DATA;
                    end
                end

                // =================================================
                // DATA BITS
                // =================================================
                TX_DATA: begin
                    // LSB first
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
                            tx_shift     <= tx_shift >> 1;
                            tx_bit_count <= tx_bit_count + 1'b1;
                        end
                    end
                end

                // =================================================
                // PARITY
                // =================================================
                TX_PARITY: begin
                    tx_serial_out <= tx_parity_bit;

                    if (baud_tick) begin
                        tx_stop_count <= '0;
                        tx_state      <= TX_STOP;
                    end
                end

                // =================================================
                // STOP
                // =================================================
                TX_STOP: begin
                    // UART STOP = HIGH
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

                // =================================================
                // DONE
                // =================================================
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
    //                         RECEIVER
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

    logic [DATA_CNT_WIDTH-1:0] rx_bit_count;
    logic [STOP_CNT_WIDTH-1:0] rx_stop_count;

    // Separate RX timing counter because RX must start
    // counting from the detected falling edge.
    logic [BAUD_CNT_WIDTH-1:0] rx_sample_counter;

    logic rx_expected_parity;
    logic rx_frame_error;

    // ------------------------------------------------------------
    // RX parity calculation
    // ------------------------------------------------------------

    always_comb begin
        case (PARITY_MODE)
            1: rx_expected_parity = ^rx_shift;       // EVEN
            2: rx_expected_parity = ~(^rx_shift);    // ODD
            default: rx_expected_parity = 1'b0;
        endcase
    end

    // ------------------------------------------------------------
    // RX FSM
    // ------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_state          <= RX_IDLE;

            rx_shift          <= '0;
            rx_data           <= '0;

            rx_bit_count      <= '0;
            rx_stop_count     <= '0;
            rx_sample_counter <= '0;

            rx_valid          <= 1'b0;

            framing_error     <= 1'b0;
            parity_error      <= 1'b0;
            overrun_error     <= 1'b0;

            rx_frame_error    <= 1'b0;
        end
        else begin

            // Error flags are event flags.
            // They remain asserted for one clock when an error occurs.
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
            overrun_error <= 1'b0;

            case (rx_state)

                // =================================================
                // IDLE
                // =================================================
                RX_IDLE: begin

                    rx_sample_counter <= '0;
                    rx_bit_count      <= '0;
                    rx_stop_count     <= '0;
                    rx_frame_error    <= 1'b0;

                    // Detect falling edge / possible start.
                    if (rx_sync == 1'b0) begin
                        rx_sample_counter <= '0;
                        rx_state <= RX_START_DETECT;
                    end
                end

                // =================================================
                // START DETECT
                // =================================================
                // Wait half a bit period.
                // If line is still LOW, accept start.
                // Otherwise it was a glitch.
                // =================================================
                RX_START_DETECT: begin

                    if (rx_sample_counter >= HALF_BAUD_DIV-1) begin

                        rx_sample_counter <= '0;

                        if (rx_sync == 1'b0) begin
                            // Valid start bit.

                            rx_shift       <= '0;
                            rx_bit_count   <= '0;
                            rx_stop_count  <= '0;
                            rx_frame_error <= 1'b0;

                            rx_state <= RX_DATA;
                        end
                        else begin
                            // False start / glitch.
                            rx_state <= RX_IDLE;
                        end
                    end
                    else begin
                        rx_sample_counter <=
                            rx_sample_counter + 1'b1;
                    end
                end

                // =================================================
                // DATA
                // =================================================
                RX_DATA: begin

                    // Sample at approximately the center
                    // of each data bit.
                    if (rx_sample_counter >= BAUD_DIV-1) begin

                        rx_sample_counter <= '0;

                        rx_shift[rx_bit_count] <= rx_sync;

                        if (rx_bit_count == DATA_BITS-1) begin

                            rx_bit_count <= '0;

                            if (PARITY_MODE != 0)
                                rx_state <= RX_PARITY;
                            else begin
                                rx_stop_count <= '0;
                                rx_state <= RX_STOP;
                            end
                        end
                        else begin
                            rx_bit_count <= rx_bit_count + 1'b1;
                        end
                    end
                    else begin
                        rx_sample_counter <=
                            rx_sample_counter + 1'b1;
                    end
                end

                // =================================================
                // PARITY
                // =================================================
                RX_PARITY: begin

                    if (rx_sample_counter >= BAUD_DIV-1) begin

                        rx_sample_counter <= '0;

                        if (rx_sync != rx_expected_parity)
                            parity_error <= 1'b1;

                        rx_stop_count <= '0;
                        rx_state <= RX_STOP;
                    end
                    else begin
                        rx_sample_counter <=
                            rx_sample_counter + 1'b1;
                    end
                end

                // =================================================
                // STOP
                // =================================================
                RX_STOP: begin

                    if (rx_sample_counter >= BAUD_DIV-1) begin

                        rx_sample_counter <= '0;

                        // Stop bit must be HIGH.
                        if (rx_sync == 1'b0) begin
                            framing_error  <= 1'b1;
                            rx_frame_error <= 1'b1;
                        end

                        if (rx_stop_count == STOP_BITS-1) begin

                            // ------------------------------------------------
                            // BYTE COMPLETE
                            // ------------------------------------------------
                            if (rx_valid) begin
                                // Previous byte is still unread.
                                // No rx_read input exists in the specified
                                // interface, so rx_valid represents the
                                // receive holding register being occupied.

                                overrun_error <= 1'b1;

                                // Keep old rx_data.
                                // New byte is discarded.
                            end
                            else begin
                                rx_data  <= rx_shift;
                                rx_valid <= 1'b1;
                            end

                            rx_state <= RX_ERROR_DONE;
                        end
                        else begin
                            rx_stop_count <= rx_stop_count + 1'b1;
                        end
                    end
                    else begin
                        rx_sample_counter <=
                            rx_sample_counter + 1'b1;
                    end
                end

                // =================================================
                // ERROR / DONE
                // =================================================
                RX_ERROR_DONE: begin
                    rx_state <= RX_IDLE;
                end

                // =================================================
                // DEFAULT
                // =================================================
                default: begin
                    rx_state <= RX_IDLE;
                end

            endcase
        end
    end

endmodule
