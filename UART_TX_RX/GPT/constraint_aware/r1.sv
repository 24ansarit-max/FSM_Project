`timescale 1ns/1ps

//======================================================================
// Parameterized UART Controller
// Target : AMD/Xilinx Artix-7
// Tool   : Vivado 2025.2
// Clock  : 100 MHz default
//
// TX FSM:
//   IDLE -> START -> DATA -> PARITY -> STOP -> DONE -> IDLE
//
// RX FSM:
//   IDLE -> START_DETECT -> DATA -> PARITY -> STOP -> ERROR_DONE -> IDLE
//
// RX uses 16x oversampling.
// The RX input is synchronized through two flip-flops marked ASYNC_REG.
//======================================================================


//======================================================================
// SHARED BAUD / 16x OVERSAMPLING TICK GENERATOR
//======================================================================

module uart_baud_gen #(
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned BAUD_RATE   = 115_200,
    parameter int unsigned OVERSAMPLE  = 16
)(
    input  logic clk,
    input  logic rst,

    output logic sample_tick,
    output logic baud_tick
);

    // Integer divider. Rounding is toward zero.
    localparam longint unsigned SAMPLE_DIV_CALC =
        CLK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE);

    localparam longint unsigned SAMPLE_DIV =
        (SAMPLE_DIV_CALC < 1) ? 1 : SAMPLE_DIV_CALC;

    localparam int unsigned CNT_WIDTH =
        (SAMPLE_DIV <= 1) ? 1 : $clog2(SAMPLE_DIV);

    localparam int unsigned PHASE_WIDTH =
        (OVERSAMPLE <= 1) ? 1 : $clog2(OVERSAMPLE);

    logic [CNT_WIDTH-1:0]   clk_count;
    logic [PHASE_WIDTH-1:0] phase_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            clk_count   <= '0;
            phase_count <= '0;
            sample_tick <= 1'b0;
            baud_tick   <= 1'b0;
        end
        else begin

            // Registered one-clock tick pulses.
            sample_tick <= 1'b0;
            baud_tick   <= 1'b0;

            if (clk_count == SAMPLE_DIV-1) begin

                clk_count   <= '0;
                sample_tick <= 1'b1;

                if (phase_count == OVERSAMPLE-1) begin
                    phase_count <= '0;
                    baud_tick   <= 1'b1;
                end
                else begin
                    phase_count <= phase_count + 1'b1;
                end

            end
            else begin
                clk_count <= clk_count + 1'b1;
            end
        end
    end

endmodule


//======================================================================
// UART CONTROLLER
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

    // TX interface
    input  logic                 tx_start,
    input  logic [DATA_BITS-1:0] tx_data,

    // RX serial input
    input  logic                 rx_serial_in,

    // TX outputs
    output logic                 tx_serial_out,
    output logic                 tx_busy,
    output logic                 tx_done,

    // RX outputs
    output logic [DATA_BITS-1:0] rx_data,
    output logic                 rx_valid,
    output logic                 framing_error,
    output logic                 parity_error,
    output logic                 overrun_error
);

    //==================================================================
    // Parameter-derived widths
    //==================================================================

    localparam int unsigned BIT_COUNT_WIDTH =
        (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);

    localparam int unsigned STOP_COUNT_WIDTH =
        (STOP_BITS <= 1) ? 1 : $clog2(STOP_BITS);

    localparam int unsigned SAMPLE_COUNT_WIDTH =
        $clog2(16);

    localparam logic [BIT_COUNT_WIDTH-1:0] LAST_DATA_BIT =
        DATA_BITS - 1;

    localparam logic [STOP_COUNT_WIDTH-1:0] LAST_STOP_BIT =
        STOP_BITS - 1;

    localparam logic [SAMPLE_COUNT_WIDTH-1:0] HALF_SAMPLE_COUNT =
        4'd7;

    localparam logic [SAMPLE_COUNT_WIDTH-1:0] LAST_SAMPLE_COUNT =
        4'd15;


    //==================================================================
    // Shared baud generator
    //==================================================================

    logic sample_tick;
    logic baud_tick;

    uart_baud_gen #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (16)
    ) u_baud_gen (
        .clk        (clk),
        .rst        (rst),
        .sample_tick(sample_tick),
        .baud_tick  (baud_tick)
    );


    //==================================================================
    // RX asynchronous input synchronizer
    //==================================================================

    (* ASYNC_REG = "TRUE" *) logic rx_meta;
    (* ASYNC_REG = "TRUE" *) logic rx_sync;

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
    // TX FSM
    //==================================================================

    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP,
        TX_DONE
    } tx_state_t;

    tx_state_t tx_state;
    tx_state_t tx_next_state;


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

    rx_state_t rx_state;
    rx_state_t rx_next_state;


    //==================================================================
    // TX datapath registers
    //==================================================================

    logic [DATA_BITS-1:0] tx_shift_reg;

    logic [BIT_COUNT_WIDTH-1:0] tx_bit_count;

    logic [STOP_COUNT_WIDTH-1:0] tx_stop_count;

    logic tx_parity_bit;


    //==================================================================
    // RX datapath registers
    //==================================================================

    logic [DATA_BITS-1:0] rx_shift_reg;

    logic [BIT_COUNT_WIDTH-1:0] rx_bit_count;

    logic [STOP_COUNT_WIDTH-1:0] rx_stop_count;

    logic [SAMPLE_COUNT_WIDTH-1:0] rx_sample_count;

    logic rx_parity_accum;

    logic rx_parity_bad;

    logic rx_frame_bad;


    //==================================================================
    // TX NEXT-STATE LOGIC
    //==================================================================

    always_comb begin

        tx_next_state = tx_state;

        case (tx_state)

            TX_IDLE: begin
                if (tx_start)
                    tx_next_state = TX_START;
            end

            TX_START: begin
                if (baud_tick)
                    tx_next_state = TX_DATA;
            end

            TX_DATA: begin
                if (baud_tick &&
                    (tx_bit_count == LAST_DATA_BIT)) begin

                    if (PARITY_MODE == "none")
                        tx_next_state = TX_STOP;
                    else
                        tx_next_state = TX_PARITY;

                end
            end

            TX_PARITY: begin
                if (baud_tick)
                    tx_next_state = TX_STOP;
            end

            TX_STOP: begin
                if (baud_tick &&
                    (tx_stop_count == LAST_STOP_BIT))
                    tx_next_state = TX_DONE;
            end

            TX_DONE: begin
                tx_next_state = TX_IDLE;
            end

            default: begin
                tx_next_state = TX_IDLE;
            end

        endcase
    end


    //==================================================================
    // TX STATE + DATAPATH + REGISTERED OUTPUTS
    //==================================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            tx_state      <= TX_IDLE;

            tx_shift_reg  <= '0;
            tx_bit_count  <= '0;
            tx_stop_count <= '0;
            tx_parity_bit <= 1'b0;

            tx_serial_out <= 1'b1;
            tx_busy       <= 1'b0;
            tx_done       <= 1'b0;

        end
        else begin

            tx_state <= tx_next_state;

            // tx_done is a one-clock pulse.
            tx_done <= 1'b0;


            //----------------------------------------------------------
            // Accept a new TX request only while idle.
            // tx_start while busy is therefore ignored.
            //----------------------------------------------------------

            if ((tx_state == TX_IDLE) && tx_start) begin

                tx_shift_reg  <= tx_data;
                tx_bit_count  <= '0;
                tx_stop_count <= '0;

                // XOR = parity bit for even parity.
                tx_parity_bit <= ^tx_data;

            end


            //----------------------------------------------------------
            // Registered TX outputs.
            //----------------------------------------------------------

            case (tx_next_state)

                TX_IDLE: begin
                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;
                end

                TX_START: begin
                    tx_serial_out <= 1'b0;
                    tx_busy       <= 1'b1;
                end

                TX_DATA: begin
                    tx_serial_out <= tx_shift_reg[0];
                    tx_busy       <= 1'b1;
                end

                TX_PARITY: begin

                    if (PARITY_MODE == "odd")
                        tx_serial_out <= ~tx_parity_bit;
                    else
                        tx_serial_out <= tx_parity_bit;

                    tx_busy <= 1'b1;

                end

                TX_STOP: begin
                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b1;
                end

                TX_DONE: begin
                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;
                    tx_done       <= 1'b1;
                end

                default: begin
                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;
                end

            endcase


            //----------------------------------------------------------
            // TX data shift.
            //----------------------------------------------------------

            if ((tx_state == TX_DATA) && baud_tick) begin

                if (tx_bit_count < LAST_DATA_BIT) begin

                    tx_shift_reg <= {
                        1'b0,
                        tx_shift_reg[DATA_BITS-1:1]
                    };

                    tx_bit_count <= tx_bit_count + 1'b1;

                end

            end


            //----------------------------------------------------------
            // TX stop-bit counter.
            //----------------------------------------------------------

            if (tx_state != TX_STOP) begin
                tx_stop_count <= '0;
            end
            else if (baud_tick &&
                     (tx_stop_count < LAST_STOP_BIT)) begin

                tx_stop_count <= tx_stop_count + 1'b1;

            end

        end
    end


    //==================================================================
    // RX NEXT-STATE LOGIC
    //==================================================================

    always_comb begin

        rx_next_state = rx_state;

        case (rx_state)

            //----------------------------------------------------------
            // Waiting for a falling edge/start indication.
            //----------------------------------------------------------

            RX_IDLE: begin

                if (sample_tick && !rx_sync)
                    rx_next_state = RX_START_DETECT;

            end


            //----------------------------------------------------------
            // Wait half a bit and verify that the line is still low.
            // This rejects short glitches.
            //----------------------------------------------------------

            RX_START_DETECT: begin

                if (sample_tick &&
                    (rx_sample_count == HALF_SAMPLE_COUNT)) begin

                    if (!rx_sync)
                        rx_next_state = RX_DATA;
                    else
                        rx_next_state = RX_IDLE;

                end

            end


            //----------------------------------------------------------
            // Sample each data bit every 16x sample ticks.
            //----------------------------------------------------------

            RX_DATA: begin

                if (sample_tick &&
                    (rx_sample_count == LAST_SAMPLE_COUNT) &&
                    (rx_bit_count == LAST_DATA_BIT)) begin

                    if (PARITY_MODE == "none")
                        rx_next_state = RX_STOP;
                    else
                        rx_next_state = RX_PARITY;

                end

            end


            //----------------------------------------------------------
            // Sample parity bit.
            //----------------------------------------------------------

            RX_PARITY: begin

                if (sample_tick &&
                    (rx_sample_count == LAST_SAMPLE_COUNT))

                    rx_next_state = RX_STOP;

            end


            //----------------------------------------------------------
            // Sample one or two stop bits.
            //----------------------------------------------------------

            RX_STOP: begin

                if (sample_tick &&
                    (rx_sample_count == LAST_SAMPLE_COUNT) &&
                    (rx_stop_count == LAST_STOP_BIT))

                    rx_next_state = RX_ERROR_DONE;

            end


            //----------------------------------------------------------
            // Report result and return to idle.
            //----------------------------------------------------------

            RX_ERROR_DONE: begin
                rx_next_state = RX_IDLE;
            end


            default: begin
                rx_next_state = RX_IDLE;
            end

        endcase
    end


    //==================================================================
    // RX STATE + DATAPATH + REGISTERED OUTPUTS
    //==================================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            rx_state        <= RX_IDLE;

            rx_shift_reg    <= '0;
            rx_bit_count    <= '0;
            rx_stop_count   <= '0;
            rx_sample_count <= '0;

            rx_parity_accum <= 1'b0;
            rx_parity_bad   <= 1'b0;
            rx_frame_bad    <= 1'b0;

            rx_data         <= '0;

            rx_valid        <= 1'b0;
            framing_error   <= 1'b0;
            parity_error    <= 1'b0;
            overrun_error   <= 1'b0;

        end
        else begin

            rx_state <= rx_next_state;


            //----------------------------------------------------------
            // All pulse/error outputs are registered.
            // Error flags are event pulses and are therefore
            // glitch-free.
            //----------------------------------------------------------

            rx_valid       <= 1'b0;
            framing_error  <= 1'b0;
            parity_error   <= 1'b0;
            overrun_error  <= 1'b0;


            //----------------------------------------------------------
            // Beginning of a new frame.
            //----------------------------------------------------------

            if ((rx_state == RX_IDLE) &&
                (rx_next_state == RX_START_DETECT)) begin

                rx_sample_count <= '0;
                rx_bit_count    <= '0;
                rx_stop_count   <= '0;

                rx_parity_accum <= 1'b0;
                rx_parity_bad   <= 1'b0;
                rx_frame_bad    <= 1'b0;

            end


            //----------------------------------------------------------
            // Start-bit midpoint counter.
            //----------------------------------------------------------

            if ((rx_state == RX_START_DETECT) &&
                sample_tick) begin

                if (rx_sample_count < HALF_SAMPLE_COUNT)
                    rx_sample_count <= rx_sample_count + 1'b1;
                else
                    rx_sample_count <= '0;

            end


            //----------------------------------------------------------
            // Data-bit sampling.
            //----------------------------------------------------------

            if ((rx_state == RX_DATA) &&
                sample_tick) begin

                if (rx_sample_count == LAST_SAMPLE_COUNT) begin

                    rx_sample_count <= '0;

                    rx_shift_reg[rx_bit_count] <= rx_sync;


                    if (PARITY_MODE != "none") begin
                        rx_parity_accum <=
                            rx_parity_accum ^ rx_sync;
                    end


                    if (rx_bit_count < LAST_DATA_BIT)
                        rx_bit_count <= rx_bit_count + 1'b1;

                end
                else begin

                    rx_sample_count <=
                        rx_sample_count + 1'b1;

                end

            end


            //----------------------------------------------------------
            // Parity-bit sampling.
            //----------------------------------------------------------

            if ((rx_state == RX_PARITY) &&
                sample_tick) begin

                if (rx_sample_count == LAST_SAMPLE_COUNT) begin

                    rx_sample_count <= '0;


                    if (PARITY_MODE == "even") begin

                        if (rx_sync != rx_parity_accum)
                            rx_parity_bad <= 1'b1;

                    end
                    else if (PARITY_MODE == "odd") begin

                        if (rx_sync != ~rx_parity_accum)
                            rx_parity_bad <= 1'b1;

                    end

                end
                else begin

                    rx_sample_count <=
                        rx_sample_count + 1'b1;

                end

            end


            //----------------------------------------------------------
            // Stop-bit sampling.
            //----------------------------------------------------------

            if ((rx_state == RX_STOP) &&
                sample_tick) begin

                if (rx_sample_count == LAST_SAMPLE_COUNT) begin

                    rx_sample_count <= '0;


                    if (!rx_sync)
                        rx_frame_bad <= 1'b1;


                    if (rx_stop_count < LAST_STOP_BIT)
                        rx_stop_count <= rx_stop_count + 1'b1;

                end
                else begin

                    rx_sample_count <=
                        rx_sample_count + 1'b1;

                end

            end


            //----------------------------------------------------------
            // Frame result.
            //----------------------------------------------------------

            if (rx_state == RX_ERROR_DONE) begin

                if (rx_frame_bad)
                    framing_error <= 1'b1;

                if (rx_parity_bad)
                    parity_error <= 1'b1;


                //------------------------------------------------------
                // Valid frame.
                //
                // rx_valid is a one-cycle notification that rx_data
                // has been updated.
                //
                // Because the requested interface has no rx_read/
                // rx_ready input, there is no externally observable
                // "unread" state. The overrun condition below detects
                // a new completed byte while the previous valid event
                // is still active.
                //------------------------------------------------------

                if (!rx_frame_bad && !rx_parity_bad) begin

                    if (rx_valid) begin
                        overrun_error <= 1'b1;
                    end
                    else begin
                        rx_data  <= rx_shift_reg;
                        rx_valid <= 1'b1;
                    end

                end

            end

        end
    end

endmodule
