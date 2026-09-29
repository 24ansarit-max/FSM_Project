`timescale 1ns/1ps

//======================================================================
// BAUD TICK GENERATOR
//======================================================================
module uart_baud_gen #(
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned BAUD_RATE   = 115_200,
    parameter int unsigned OVERSAMPLE  = 1
)(
    input  logic clk,
    input  logic rst,
    output logic tick
);

    localparam int unsigned DIV_CALC =
        CLK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE);

    localparam int unsigned DIV =
        (DIV_CALC < 1) ? 1 : DIV_CALC;

    localparam int unsigned CNT_WIDTH =
        (DIV <= 1) ? 1 : $clog2(DIV);

    logic [CNT_WIDTH-1:0] cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            cnt  <= '0;
            tick <= 1'b0;
        end
        else if (cnt == DIV-1) begin
            cnt  <= '0;
            tick <= 1'b1;
        end
        else begin
            cnt  <= cnt + 1'b1;
            tick <= 1'b0;
        end
    end

endmodule


//======================================================================
// UART TRANSMITTER
//
// IDLE -> START -> DATA -> PARITY -> STOP -> DONE -> IDLE
//======================================================================
module uart_tx #(
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned BAUD_RATE   = 115_200,
    parameter int unsigned DATA_BITS   = 8,
    parameter string       PARITY_MODE = "none",
    parameter int unsigned STOP_BITS   = 1
)(
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 tx_start,
    input  logic [DATA_BITS-1:0] tx_data,

    output logic                 tx_serial_out,
    output logic                 tx_busy,
    output logic                 tx_done
);

    //==================================================================
    // Baud tick
    //==================================================================

    logic baud_tick;

    uart_baud_gen #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (1)
    ) baud_gen (
        .clk  (clk),
        .rst  (rst),
        .tick (baud_tick)
    );

    //==================================================================
    // FSM
    //==================================================================

    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        PARITY,
        STOP,
        DONE
    } state_t;

    state_t state, next_state;

    //==================================================================
    // Registers
    //==================================================================

    logic [DATA_BITS-1:0] shreg;
    logic parity_bit;

    localparam int BIT_WIDTH =
        (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);

    localparam int STOP_WIDTH =
        (STOP_BITS <= 1) ? 1 : $clog2(STOP_BITS);

    logic [BIT_WIDTH-1:0]  bit_idx;
    logic [STOP_WIDTH-1:0] stop_idx;

    //==================================================================
    // Sequential logic
    //==================================================================

    always_ff @(posedge clk) begin

        if (rst) begin
            state      <= IDLE;
            shreg      <= '0;
            parity_bit <= 1'b0;
            bit_idx    <= '0;
            stop_idx   <= '0;
        end

        else begin

            state <= next_state;

            // Load a new byte only when idle.
            if (state == IDLE && tx_start) begin
                shreg      <= tx_data;
                parity_bit <= ^tx_data;
                bit_idx    <= '0;
                stop_idx   <= '0;
            end

            // Shift after each transmitted data bit.
            if (state == DATA && baud_tick) begin
                if (bit_idx < DATA_BITS-1) begin
                    shreg   <= {1'b0, shreg[DATA_BITS-1:1]};
                    bit_idx <= bit_idx + 1'b1;
                end
            end

            // Count stop bits.
            if (state == STOP && baud_tick) begin
                if (stop_idx < STOP_BITS-1)
                    stop_idx <= stop_idx + 1'b1;
            end

        end
    end

    //==================================================================
    // Next-state and output logic
    //==================================================================

    always_comb begin

        next_state    = state;
        tx_serial_out = 1'b1;
        tx_busy       = 1'b0;
        tx_done       = 1'b0;

        case (state)

            IDLE: begin
                tx_serial_out = 1'b1;
                tx_busy       = 1'b0;

                if (tx_start)
                    next_state = START;
            end

            START: begin
                tx_serial_out = 1'b0;
                tx_busy       = 1'b1;

                if (baud_tick)
                    next_state = DATA;
            end

            DATA: begin
                tx_serial_out = shreg[0];
                tx_busy       = 1'b1;

                if (baud_tick &&
                    bit_idx == DATA_BITS-1) begin

                    if (PARITY_MODE == "none")
                        next_state = STOP;
                    else
                        next_state = PARITY;

                end
            end

            PARITY: begin
                tx_busy = 1'b1;

                if (PARITY_MODE == "even")
                    tx_serial_out = parity_bit;
                else
                    tx_serial_out = ~parity_bit;

                if (baud_tick)
                    next_state = STOP;
            end

            STOP: begin
                tx_serial_out = 1'b1;
                tx_busy       = 1'b1;

                if (baud_tick &&
                    stop_idx == STOP_BITS-1)
                    next_state = DONE;
            end

            DONE: begin
                tx_serial_out = 1'b1;
                tx_busy       = 1'b0;
                tx_done       = 1'b1;

                next_state = IDLE;
            end

            default: begin
                next_state    = IDLE;
                tx_serial_out = 1'b1;
                tx_busy       = 1'b0;
                tx_done       = 1'b0;
            end

        endcase

    end

endmodule


//======================================================================
// UART RECEIVER
//
// IDLE -> START_DETECT -> DATA -> PARITY -> STOP -> ERROR_DONE
//   ^                                                    |
//   |____________________________________________________|
//
// RX uses 16x oversampling.
//======================================================================
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

    output logic [DATA_BITS-1:0] rx_data,
    output logic                 rx_valid,
    output logic                 framing_error,
    output logic                 parity_error,
    output logic                 overrun_error
);

    //==================================================================
    // 16x sampling tick
    //==================================================================

    logic sample_tick;

    uart_baud_gen #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) baud_gen (
        .clk  (clk),
        .rst  (rst),
        .tick (sample_tick)
    );

    //==================================================================
    // Synchronizer
    //==================================================================

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

    //==================================================================
    // RX FSM
    //==================================================================

    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START_DETECT,
        RX_DATA,
        RX_PARITY,
        RX_STOP,
        RX_ERROR_DONE
    } rx_state_t;

    rx_state_t state, next_state;

    //==================================================================
    // RX registers
    //==================================================================

    logic [DATA_BITS-1:0] shreg;

    // XOR of all received data bits.
    logic parity_accum;

    logic parity_bad;
    logic frame_bad;

    localparam int SAMPLE_WIDTH =
        (OVERSAMPLE <= 1) ? 1 : $clog2(OVERSAMPLE);

    localparam int BIT_WIDTH =
        (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);

    localparam int STOP_WIDTH =
        (STOP_BITS <= 1) ? 1 : $clog2(STOP_BITS);

    logic [SAMPLE_WIDTH-1:0] sample_cnt;
    logic [SAMPLE_WIDTH-1:0] start_cnt;

    logic [BIT_WIDTH-1:0]  bit_idx;
    logic [STOP_WIDTH-1:0] stop_idx;

    // One-byte receive buffer pending flag.
    logic rx_pending;

    //==================================================================
    // Sequential logic
    //==================================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state <= RX_IDLE;

            shreg        <= '0;
            parity_accum <= 1'b0;

            parity_bad <= 1'b0;
            frame_bad  <= 1'b0;

            sample_cnt <= '0;
            start_cnt  <= '0;
            bit_idx    <= '0;
            stop_idx   <= '0;

            rx_data <= '0;

            rx_valid      <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
            overrun_error <= 1'b0;

            rx_pending <= 1'b0;
        end

        else begin

            state <= next_state;

            //==========================================================
            // Start detection initialization
            //==========================================================

            if (state == RX_IDLE &&
                sample_tick &&
                !rx_sync) begin

                start_cnt    <= '0;
                sample_cnt   <= '0;
                bit_idx      <= '0;
                stop_idx     <= '0;
                parity_accum <= 1'b0;

                parity_bad <= 1'b0;
                frame_bad  <= 1'b0;
            end

            //==========================================================
            // START DETECT
            //==========================================================

            if (state == RX_START_DETECT &&
                sample_tick) begin

                if (start_cnt < (OVERSAMPLE/2)-1) begin
                    start_cnt <= start_cnt + 1'b1;
                end

            end

            //==========================================================
            // DATA
            //==========================================================

            if (state == RX_DATA &&
                sample_tick) begin

                if (sample_cnt == OVERSAMPLE-1) begin

                    sample_cnt <= '0;

                    // Sample at approximately the center.
                    shreg[bit_idx] <= rx_sync;

                    if (PARITY_MODE != "none")
                        parity_accum <= parity_accum ^ rx_sync;

                    if (bit_idx < DATA_BITS-1)
                        bit_idx <= bit_idx + 1'b1;

                end
                else begin
                    sample_cnt <= sample_cnt + 1'b1;
                end

            end

            //==========================================================
            // PARITY
            //==========================================================

            if (state == RX_PARITY &&
                sample_tick) begin

                if (sample_cnt == OVERSAMPLE-1) begin

                    sample_cnt <= '0;

                    if (PARITY_MODE == "even") begin

                        if (rx_sync != parity_accum)
                            parity_bad <= 1'b1;

                    end
                    else if (PARITY_MODE == "odd") begin

                        if (rx_sync != ~parity_accum)
                            parity_bad <= 1'b1;

                    end

                end
                else begin
                    sample_cnt <= sample_cnt + 1'b1;
                end

            end

            //==========================================================
            // STOP
            //==========================================================

            if (state == RX_STOP &&
                sample_tick) begin

                if (sample_cnt == OVERSAMPLE-1) begin

                    sample_cnt <= '0;

                    // UART stop bit must be HIGH.
                    if (!rx_sync)
                        frame_bad <= 1'b1;

                    if (stop_idx < STOP_BITS-1)
                        stop_idx <= stop_idx + 1'b1;

                end
                else begin
                    sample_cnt <= sample_cnt + 1'b1;
                end

            end

            //==========================================================
            // ERROR / DONE
            //==========================================================

            if (state == RX_ERROR_DONE) begin

                if (frame_bad)
                    framing_error <= 1'b1;

                if (parity_bad)
                    parity_error <= 1'b1;

                // Deliver only a valid frame.
                if (!frame_bad && !parity_bad) begin

                    if (rx_pending) begin
                        // Previous byte has not been consumed.
                        overrun_error <= 1'b1;
                    end
                    else begin
                        rx_data    <= shreg;
                        rx_valid   <= 1'b1;
                        rx_pending <= 1'b1;
                    end

                end

            end

        end

    end

    //==================================================================
    // RX next-state logic
    //==================================================================

    always_comb begin

        next_state = state;

        case (state)

            //==========================================================
            // IDLE
            //==========================================================

            RX_IDLE: begin

                if (sample_tick && !rx_sync)
                    next_state = RX_START_DETECT;

            end

            //==========================================================
            // START DETECT
            //
            // Wait half a UART bit and verify LOW.
            //==========================================================

            RX_START_DETECT: begin

                if (sample_tick &&
                    start_cnt == (OVERSAMPLE/2)-1) begin

                    if (!rx_sync) begin
                        next_state = RX_DATA;
                    end
                    else begin
                        // False start / glitch.
                        next_state = RX_IDLE;
                    end

                end

            end

            //==========================================================
            // DATA
            //==========================================================

            RX_DATA: begin

                if (sample_tick &&
                    sample_cnt == OVERSAMPLE-1 &&
                    bit_idx == DATA_BITS-1) begin

                    if (PARITY_MODE == "none")
                        next_state = RX_STOP;
                    else
                        next_state = RX_PARITY;

                end

            end

            //==========================================================
            // PARITY
            //==========================================================

            RX_PARITY: begin

                if (sample_tick &&
                    sample_cnt == OVERSAMPLE-1)

                    next_state = RX_STOP;

            end

            //==========================================================
            // STOP
            //==========================================================

            RX_STOP: begin

                if (sample_tick &&
                    sample_cnt == OVERSAMPLE-1 &&
                    stop_idx == STOP_BITS-1)

                    next_state = RX_ERROR_DONE;

            end

            //==========================================================
            // ERROR / DONE
            //==========================================================

            RX_ERROR_DONE: begin
                next_state = RX_IDLE;
            end

            //==========================================================
            // DEFAULT
            //==========================================================

            default: begin
                next_state = RX_IDLE;
            end

        endcase

    end

endmodule


//======================================================================
// TOP-LEVEL UART CONTROLLER
//======================================================================
module uart_controller #(
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned BAUD_RATE   = 115_200,
    parameter int unsigned DATA_BITS   = 8,
    parameter string       PARITY_MODE = "none",
    parameter int unsigned STOP_BITS   = 1
)(
    input  logic                 clk,
    input  logic                 rst,

    input  logic                 tx_start,
    input  logic [DATA_BITS-1:0] tx_data,
    input  logic                 rx_serial_in,

    output logic                 tx_serial_out,
    output logic                 tx_busy,
    output logic                 tx_done,

    output logic [DATA_BITS-1:0] rx_data,
    output logic                 rx_valid,
    output logic                 framing_error,
    output logic                 parity_error,
    output logic                 overrun_error
);

    //==================================================================
    // Transmitter
    //==================================================================

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .DATA_BITS  (DATA_BITS),
        .PARITY_MODE(PARITY_MODE),
        .STOP_BITS  (STOP_BITS)
    ) tx_inst (
        .clk           (clk),
        .rst           (rst),
        .tx_start      (tx_start),
        .tx_data       (tx_data),
        .tx_serial_out (tx_serial_out),
        .tx_busy       (tx_busy),
        .tx_done       (tx_done)
    );

    //==================================================================
    // Receiver
    //==================================================================

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .DATA_BITS  (DATA_BITS),
        .PARITY_MODE(PARITY_MODE),
        .STOP_BITS  (STOP_BITS),
        .OVERSAMPLE  (16)
    ) rx_inst (
        .clk           (clk),
        .rst           (rst),
        .rx_serial_in  (rx_serial_in),
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .framing_error (framing_error),
        .parity_error  (parity_error),
        .overrun_error (overrun_error)
    );

endmodule
