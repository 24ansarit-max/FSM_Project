`timescale 1ns/1ps

module uart_rx #(
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned BAUD_RATE   = 115_200,
    parameter int unsigned DATA_BITS   = 8,
    parameter string       PARITY_MODE = "none",
    parameter int unsigned STOP_BITS   = 1,
    parameter int unsigned OVERSAMPLE  = 16
)(
    input  logic                 clk,
    input  logic                 rst,

    input  logic                 rx_serial_in,

    // Explicitly acknowledges that rx_data was consumed.
    input  logic                 rx_read,

    output logic [DATA_BITS-1:0] rx_data,
    output logic                 rx_valid,
    output logic                 framing_error,
    output logic                 parity_error,
    output logic                 overrun_error
);

    //============================================================
    // RX baud generator
    //============================================================

    logic sample_tick;

    uart_baud_gen #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) rx_baud_gen (
        .clk  (clk),
        .rst  (rst),
        .tick (sample_tick)
    );

    //============================================================
    // 2-flop synchronizer
    //============================================================

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

    //============================================================
    // RX FSM
    //============================================================

    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START_DETECT,
        RX_DATA,
        RX_PARITY,
        RX_STOP,
        RX_ERROR_DONE
    } rx_state_t;

    rx_state_t state;

    //============================================================
    // Registers
    //============================================================

    logic [DATA_BITS-1:0] rx_shift;

    logic parity_accum;

    integer sample_count;
    integer start_count;
    integer bit_index;
    integer stop_count;

    logic frame_error_pending;
    logic parity_error_pending;

    //============================================================
    // RX FSM
    //============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state <= RX_IDLE;

            rx_shift <= '0;
            rx_data  <= '0;

            rx_valid <= 1'b0;

            framing_error <= 1'b0;
            parity_error  <= 1'b0;
            overrun_error <= 1'b0;

            parity_accum <= 1'b0;

            sample_count <= 0;
            start_count  <= 0;
            bit_index    <= 0;
            stop_count   <= 0;

            frame_error_pending  <= 1'b0;
            parity_error_pending <= 1'b0;
        end
        else begin

            //====================================================
            // Clear valid when host consumes current byte
            //====================================================

            if (rx_read && rx_valid)
                rx_valid <= 1'b0;

            case (state)

                //================================================
                // IDLE
                //================================================

                RX_IDLE: begin

                    sample_count <= 0;
                    start_count  <= 0;
                    bit_index    <= 0;
                    stop_count   <= 0;

                    frame_error_pending  <= 1'b0;
                    parity_error_pending <= 1'b0;

                    // UART idle is HIGH.
                    // LOW indicates a possible start bit.
                    if (sample_tick && !rx_sync) begin

                        start_count <= 1;

                        state <= RX_START_DETECT;
                    end
                end

                //================================================
                // START DETECT
                //================================================

                RX_START_DETECT: begin

                    if (sample_tick) begin

                        if (!rx_sync) begin

                            // Confirm LOW until the middle
                            // of the start bit.

                            if (start_count >= (OVERSAMPLE/2)-1) begin

                                sample_count <= 0;
                                bit_index    <= 0;

                                rx_shift     <= '0;
                                parity_accum <= 1'b0;

                                state <= RX_DATA;
                            end
                            else begin
                                start_count <= start_count + 1;
                            end
                        end
                        else begin

                            // The LOW pulse disappeared before
                            // midpoint: reject as a glitch.

                            start_count <= 0;
                            state <= RX_IDLE;
                        end
                    end
                end

                //================================================
                // DATA
                //================================================

                RX_DATA: begin

                    if (sample_tick) begin

                        if (sample_count == OVERSAMPLE-1) begin

                            sample_count <= 0;

                            // Sample data bit at its midpoint
                            rx_shift[bit_index] <= rx_sync;

                            if (PARITY_MODE != "none")
                                parity_accum <=
                                    parity_accum ^ rx_sync;

                            if (bit_index == DATA_BITS-1) begin

                                if (PARITY_MODE == "none") begin

                                    stop_count <= 0;
                                    state <= RX_STOP;
                                end
                                else begin

                                    state <= RX_PARITY;
                                end
                            end
                            else begin

                                bit_index <= bit_index + 1;
                            end
                        end
                        else begin

                            sample_count <= sample_count + 1;
                        end
                    end
                end

                //================================================
                // PARITY
                //================================================

                RX_PARITY: begin

                    if (sample_tick) begin

                        if (sample_count == OVERSAMPLE-1) begin

                            sample_count <= 0;

                            if (PARITY_MODE == "even") begin

                                if (rx_sync != parity_accum)
                                    parity_error_pending <= 1'b1;
                            end
                            else begin

                                if (rx_sync != ~parity_accum)
                                    parity_error_pending <= 1'b1;
                            end

                            stop_count <= 0;

                            state <= RX_STOP;
                        end
                        else begin

                            sample_count <= sample_count + 1;
                        end
                    end
                end

                //================================================
                // STOP
                //================================================

                RX_STOP: begin

                    if (sample_tick) begin

                        if (sample_count == OVERSAMPLE-1) begin

                            sample_count <= 0;

                            // Stop bit must be HIGH
                            if (!rx_sync)
                                frame_error_pending <= 1'b1;

                            if (stop_count == STOP_BITS-1) begin
                                state <= RX_ERROR_DONE;
                            end
                            else begin
                                stop_count <= stop_count + 1;
                            end
                        end
                        else begin
                            sample_count <= sample_count + 1;
                        end
                    end
                end

                //================================================
                // ERROR / DONE
                //================================================

                RX_ERROR_DONE: begin

                    // Report errors
                    if (frame_error_pending)
                        framing_error <= 1'b1;

                    if (parity_error_pending)
                        parity_error <= 1'b1;

                    // Only accept a completely valid byte
                    if (!frame_error_pending &&
                        !parity_error_pending) begin

                        if (rx_valid && !rx_read) begin

                            // Previous byte has not been consumed.
                            overrun_error <= 1'b1;

                            // Preserve old rx_data.
                            rx_valid <= 1'b1;
                        end
                        else begin

                            rx_data  <= rx_shift;
                            rx_valid <= 1'b1;
                        end
                    end

                    state <= RX_IDLE;
                end

                default: begin
                    state <= RX_IDLE;
                end

            endcase
        end
    end

endmodule
