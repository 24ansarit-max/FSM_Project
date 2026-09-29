`timescale 1ns/1ps

//======================================================================
// PARAMETERIZED UART CONTROLLER
// Target : AMD/Xilinx Artix-7
// Tool   : Vivado 2025.2
// Default: 100 MHz, 115200 baud, 8N1
//
// TX FSM:
//   IDLE -> START -> DATA -> PARITY -> STOP -> DONE -> IDLE
//
// RX FSM:
//   IDLE -> START_DETECT -> DATA -> PARITY -> STOP
//        -> ERROR_DONE -> IDLE
//
// RX uses 16x oversampling.
// rx_serial_in is synchronized by two flip-flops marked ASYNC_REG.
//
// rx_read:
//   Acknowledge/consume the byte indicated by rx_valid.
//   This is required to implement a meaningful RX overrun condition.
//
// Error flags are sticky until reset.
//======================================================================


//======================================================================
// SHARED BAUD / OVERSAMPLING TICK GENERATOR
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

    // Sample clock = BAUD_RATE * OVERSAMPLE.
    //
    // Example:
    // 100 MHz / (115200 * 16) = 54.253...
    //
    // Integer divider = 54.
    //
    // No hardcoded baud divider is used.

    localparam longint unsigned DIV_CALC =
        CLK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE);

    localparam longint unsigned DIV_VALUE =
        (DIV_CALC < 1) ? 1 : DIV_CALC;

    localparam int unsigned DIV_WIDTH =
        (DIV_VALUE <= 1) ? 1 : $clog2(DIV_VALUE);

    localparam int unsigned PHASE_WIDTH =
        (OVERSAMPLE <= 1) ? 1 : $clog2(OVERSAMPLE);

    logic [DIV_WIDTH-1:0]   div_count;
    logic [PHASE_WIDTH-1:0] phase_count;

    always_ff @(posedge clk) begin

        if (rst) begin
            div_count   <= '0;
            phase_count <= '0;
            sample_tick <= 1'b0;
            baud_tick   <= 1'b0;
        end
        else begin

            // Registered one-clock pulses.
            sample_tick <= 1'b0;
            baud_tick   <= 1'b0;

            if (div_count == DIV_VALUE - 1) begin

                div_count   <= '0;
                sample_tick <= 1'b1;

                if (phase_count == OVERSAMPLE - 1) begin
                    phase_count <= '0;
                    baud_tick   <= 1'b1;
                end
                else begin
                    phase_count <= phase_count + 1'b1;
                end

            end
            else begin
                div_count <= div_count + 1'b1;
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

    // RX acknowledge/read handshake
    input  logic                 rx_read,

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

    localparam int unsigned DATA_COUNT_WIDTH =
        (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);

    localparam int unsigned STOP_COUNT_WIDTH =
        (STOP_BITS <= 1) ? 1 : $clog2(STOP_BITS);

    localparam int unsigned SAMPLE_COUNT_WIDTH =
        $clog2(16);

    // Explicitly sized terminal values.
    localparam logic [DATA_COUNT_WIDTH-1:0] DATA_LAST =
        DATA_BITS - 1;

    localparam logic [STOP_COUNT_WIDTH-1:0] STOP_LAST =
        STOP_BITS - 1;

    localparam logic [SAMPLE_COUNT_WIDTH-1:0] SAMPLE_LAST =
        4'd15;

    // 16x oversampling midpoint.
    localparam logic [SAMPLE_COUNT_WIDTH-1:0] START_MIDPOINT =
        4'd7;


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
    // Asynchronous RX input synchronizer
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

    logic [DATA_COUNT_WIDTH-1:0] tx_bit_count;

    logic [STOP_COUNT_WIDTH-1:0] tx_stop_count;

    logic tx_parity_bit;


    //==================================================================
    // RX datapath registers
    //==================================================================

    logic [DATA_BITS-1:0] rx_shift_reg;

    logic [DATA_COUNT_WIDTH-1:0] rx_bit_count;

    logic [STOP_COUNT_WIDTH-1:0] rx_stop_count;

    logic [SAMPLE_COUNT_WIDTH-1:0] rx_sample_count;

    logic rx_parity_accum;
    logic rx_parity_bad;
    logic rx_frame_bad;

    // Indicates rx_data contains an unread byte.
    logic rx_pending;


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
                    (tx_bit_count == DATA_LAST)) begin

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
                    (tx_stop_count == STOP_LAST))

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
    // TX STATE REGISTER + DATAPATH + REGISTERED OUTPUTS
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

            //----------------------------------------------------------
            // State register
            //----------------------------------------------------------

            tx_state <= tx_next_state;


            //----------------------------------------------------------
            // One-cycle done pulse
            //----------------------------------------------------------

            tx_done <= 1'b0;


            //----------------------------------------------------------
            // Load data only when idle.
            // tx_start while busy is ignored.
            //----------------------------------------------------------

            if ((tx_state == TX_IDLE) && tx_start) begin

                tx_shift_reg  <= tx_data;
                tx_bit_count  <= '0;
                tx_stop_count <= '0;

                // Even parity bit.
                tx_parity_bit <= ^tx_data;

            end


            //----------------------------------------------------------
            // Registered TX output logic
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
            // TX shift register
            //----------------------------------------------------------

            if ((tx_state == TX_DATA) && baud_tick) begin

                if (tx_bit_count < DATA_LAST) begin

                    tx_shift_reg <= {
                        1'b0,
                        tx_shift_reg[DATA_BITS-1:1]
                    };

                    tx_bit_count <=
                        tx_bit_count + 1'b1;

                end

            end


            //----------------------------------------------------------
            // TX stop-bit counter
            //----------------------------------------------------------

            if (tx_state != TX_STOP) begin

                tx_stop_count <= '0;

            end
            else if (baud_tick &&
                     (tx_stop_count < STOP_LAST)) begin

                tx_stop_count <=
                    tx_stop_count + 1'b1;

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
            // IDLE
            //----------------------------------------------------------

            RX_IDLE: begin

                if (sample_tick && !rx_sync)
                    rx_next_state = RX_START_DETECT;

            end


            //----------------------------------------------------------
            // START DETECT
            //
            // A falling line is not immediately accepted.
            // The receiver waits approximately half a bit and
            // verifies that the line is still LOW.
            //----------------------------------------------------------

            RX_START_DETECT: begin

                if (sample_tick &&
                    (rx_sample_count == START_MIDPOINT)) begin

                    if (!rx_sync)
                        rx_next_state = RX_DATA;
                    else
                        rx_next_state = RX_IDLE;

                end

            end


            //----------------------------------------------------------
            // DATA
            //----------------------------------------------------------

            RX_DATA: begin

                if (sample_tick &&
                    (rx_sample_count == SAMPLE_LAST) &&
                    (rx_bit_count == DATA_LAST)) begin

                    if (PARITY_MODE == "none")
                        rx_next_state = RX_STOP;
                    else
                        rx_next_state = RX_PARITY;

                end

            end


            //----------------------------------------------------------
            // PARITY
            //----------------------------------------------------------

            RX_PARITY: begin

                if (sample_tick &&
                    (rx_sample_count == SAMPLE_LAST))

                    rx_next_state = RX_STOP;

            end


            //----------------------------------------------------------
            // STOP
            //----------------------------------------------------------

            RX_STOP: begin

                if (sample_tick &&
                    (rx_sample_count == SAMPLE_LAST) &&
                    (rx_stop_count == STOP_LAST))

                    rx_next_state = RX_ERROR_DONE;

            end


            //----------------------------------------------------------
            // ERROR / DONE
            //----------------------------------------------------------

            RX_ERROR_DONE: begin

                rx_next_state = RX_IDLE;

            end


            //----------------------------------------------------------
            // Recovery
            //----------------------------------------------------------

            default: begin

                rx_next_state = RX_IDLE;

            end

        endcase

    end


    //==================================================================
    // RX STATE REGISTER + DATAPATH + REGISTERED OUTPUTS
    //==================================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            //----------------------------------------------------------
            // State
            //----------------------------------------------------------

            rx_state <= RX_IDLE;


            //----------------------------------------------------------
            // Datapath
            //----------------------------------------------------------

            rx_shift_reg    <= '0;
            rx_bit_count    <= '0;
            rx_stop_count   <= '0;
            rx_sample_count <= '0;

            rx_parity_accum <= 1'b0;
            rx_parity_bad   <= 1'b0;
            rx_frame_bad    <= 1'b0;


            //----------------------------------------------------------
            // RX outputs
            //----------------------------------------------------------

            rx_data <= '0;

            rx_valid      <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
            overrun_error <= 1'b0;

            rx_pending <= 1'b0;

        end
        else begin

            //----------------------------------------------------------
            // State register
            //----------------------------------------------------------

            rx_state <= rx_next_state;


            //----------------------------------------------------------
            // rx_valid is a one-cycle pulse.
            //----------------------------------------------------------

            rx_valid <= 1'b0;


            //----------------------------------------------------------
            // RX read/acknowledge.
            //
            // Error flags remain sticky until reset.
            //----------------------------------------------------------

            if (rx_read)
                rx_pending <= 1'b0;


            //----------------------------------------------------------
            // New frame detected.
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

                if (rx_sample_count < START_MIDPOINT)

                    rx_sample_count <=
                        rx_sample_count + 1'b1;

                else

                    rx_sample_count <= '0;

            end


            //----------------------------------------------------------
            // DATA sampling
            //----------------------------------------------------------

            if ((rx_state == RX_DATA) &&
                sample_tick) begin

                if (rx_sample_count == SAMPLE_LAST) begin

                    rx_sample_count <= '0;

                    // UART data is LSB first.
                    rx_shift_reg[rx_bit_count] <= rx_sync;


                    if (PARITY_MODE != "none") begin

                        rx_parity_accum <=
                            rx_parity_accum ^ rx_sync;

                    end


                    if (rx_bit_count < DATA_LAST) begin

                        rx_bit_count <=
                            rx_bit_count + 1'b1;

                    end

                end
                else begin

                    rx_sample_count <=
                        rx_sample_count + 1'b1;

                end

            end


            //----------------------------------------------------------
            // PARITY sampling
            //----------------------------------------------------------

            if ((rx_state == RX_PARITY) &&
                sample_tick) begin

                if (rx_sample_count == SAMPLE_LAST) begin

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
            // STOP sampling
            //----------------------------------------------------------

            if ((rx_state == RX_STOP) &&
                sample_tick) begin

                if (rx_sample_count == SAMPLE_LAST) begin

                    rx_sample_count <= '0;


                    // Stop bit must be HIGH.
                    if (!rx_sync)
                        rx_frame_bad <= 1'b1;


                    if (rx_stop_count < STOP_LAST) begin

                        rx_stop_count <=
                            rx_stop_count + 1'b1;

                    end

                end
                else begin

                    rx_sample_count <=
                        rx_sample_count + 1'b1;

                end

            end


            //----------------------------------------------------------
            // Frame completion
            //----------------------------------------------------------

            if (rx_state == RX_ERROR_DONE) begin

                //------------------------------------------------------
                // Framing error
                //------------------------------------------------------

                if (rx_frame_bad)
                    framing_error <= 1'b1;


                //------------------------------------------------------
                // Parity error
                //------------------------------------------------------

                if (rx_parity_bad)
                    parity_error <= 1'b1;


                //------------------------------------------------------
                // Valid frame
                //------------------------------------------------------

                if (!rx_frame_bad && !rx_parity_bad) begin

                    //--------------------------------------------------
                    // If old byte has not been consumed and rx_read
                    // is not being asserted in this cycle, report
                    // overrun.
                    //--------------------------------------------------

                    if (rx_pending && !rx_read) begin

                        overrun_error <= 1'b1;

                    end

                    //--------------------------------------------------
                    // If the old byte is being consumed now, the new
                    // byte can replace it without an overrun.
                    //--------------------------------------------------

                    else begin

                        rx_data    <= rx_shift_reg;
                        rx_valid   <= 1'b1;
                        rx_pending <= 1'b1;

                    end

                end

            end

        end

    end

endmodule
