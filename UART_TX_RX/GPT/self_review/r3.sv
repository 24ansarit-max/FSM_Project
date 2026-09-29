`timescale 1ns/1ps

//============================================================
// Parameterized UART Controller
//
// Target : AMD/Xilinx Artix-7
// Tool   : Vivado 2025.2
//
// Default:
//   CLK_FREQ_HZ = 100 MHz
//   BAUD_RATE   = 115200
//   DATA_BITS   = 8
//   PARITY_MODE = "NONE"
//   STOP_BITS   = 1
//
// RX overrun handling:
//   rx_read is added as the byte-consume acknowledge.
//============================================================


//============================================================
// SHARED 16x OVERSAMPLING BAUD GENERATOR
//============================================================
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

    localparam longint unsigned TICK_RATE =
        longint'(BAUD_RATE) * longint'(OVERSAMPLE);

    // Rounded divider:
    // round(CLK_FREQ_HZ / TICK_RATE)
    localparam longint unsigned DIV_CALC =
        (longint'(CLK_FREQ_HZ) + (TICK_RATE / 2))
        / TICK_RATE;

    localparam int unsigned DIV_VALUE =
        (DIV_CALC < 1) ? 1 : int'(DIV_CALC);

    localparam int DIV_W =
        (DIV_VALUE <= 1) ? 1 : $clog2(DIV_VALUE);

    localparam int PHASE_W =
        (OVERSAMPLE <= 1) ? 1 : $clog2(OVERSAMPLE);

    logic [DIV_W-1:0]   div_cnt;
    logic [PHASE_W-1:0] phase_cnt;

    always_ff @(posedge clk) begin

        if (rst) begin
            div_cnt     <= '0;
            phase_cnt   <= '0;
            sample_tick <= 1'b0;
            baud_tick   <= 1'b0;
        end
        else begin

            sample_tick <= 1'b0;
            baud_tick   <= 1'b0;

            if (div_cnt == DIV_VALUE - 1) begin

                div_cnt     <= '0;
                sample_tick <= 1'b1;

                if (phase_cnt == OVERSAMPLE - 1) begin
                    phase_cnt <= '0;
                    baud_tick <= 1'b1;
                end
                else begin
                    phase_cnt <= phase_cnt + 1'b1;
                end

            end
            else begin
                div_cnt <= div_cnt + 1'b1;
            end

        end

    end

endmodule


//============================================================
// UART CONTROLLER
//============================================================
module uart_controller #(
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned BAUD_RATE   = 115_200,
    parameter int unsigned DATA_BITS   = 8,
    parameter string       PARITY_MODE = "NONE",
    parameter int unsigned STOP_BITS   = 1
)(
    input  logic clk,
    input  logic rst,

    // TX interface
    input  logic                 tx_start,
    input  logic [DATA_BITS-1:0] tx_data,

    // RX interface
    input  logic                 rx_serial_in,

    // Added for true overrun detection.
    // Pulse HIGH when the currently stored rx_data
    // has been consumed.
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

    //========================================================
    // PARAMETERS
    //========================================================
    localparam int unsigned OVERSAMPLE = 16;

    localparam int DATA_CNT_W =
        (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);

    localparam int STOP_CNT_W =
        (STOP_BITS <= 1) ? 1 : $clog2(STOP_BITS);

    localparam int SAMPLE_CNT_W =
        (OVERSAMPLE <= 1) ? 1 : $clog2(OVERSAMPLE);

    localparam logic [DATA_CNT_W-1:0] DATA_LAST =
        DATA_BITS - 1;

    localparam logic [STOP_CNT_W-1:0] STOP_LAST =
        STOP_BITS - 1;

    localparam logic [SAMPLE_CNT_W-1:0] HALF_SAMPLE =
        (OVERSAMPLE / 2) - 1;

    localparam logic [SAMPLE_CNT_W-1:0] FULL_SAMPLE =
        OVERSAMPLE - 1;


    //========================================================
    // SHARED BAUD GENERATOR
    //========================================================
    logic sample_tick;
    logic baud_tick;

    uart_baud_gen #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_uart_baud_gen (
        .clk        (clk),
        .rst        (rst),
        .sample_tick(sample_tick),
        .baud_tick  (baud_tick)
    );


    //========================================================
    // RX INPUT SYNCHRONIZER
    //========================================================
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


    //========================================================
    // TX FSM
    //========================================================
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


    //========================================================
    // TX DATAPATH
    //========================================================
    logic [DATA_BITS-1:0] tx_shift_reg;

    logic [DATA_CNT_W-1:0] tx_bit_cnt;

    logic [STOP_CNT_W-1:0] tx_stop_cnt;

    logic tx_parity_bit;


    //========================================================
    // TX PARITY FUNCTION
    //========================================================
    function automatic logic calc_parity(
        input logic [DATA_BITS-1:0] data_value
    );

        logic p;

        begin

            p = ^data_value;

            if (PARITY_MODE == "ODD")
                calc_parity = ~p;
            else
                calc_parity = p;

        end

    endfunction


    //========================================================
    // TX NEXT STATE LOGIC
    //========================================================
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
                    (tx_bit_cnt == DATA_LAST)) begin

                    if (PARITY_MODE == "NONE")
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
                    (tx_stop_cnt == STOP_LAST)) begin

                    tx_next_state = TX_DONE;

                end

            end


            TX_DONE: begin

                tx_next_state = TX_IDLE;

            end


            default: begin

                tx_next_state = TX_IDLE;

            end

        endcase

    end


    //========================================================
    // TX STATE REGISTER + DATAPATH + REGISTERED OUTPUTS
    //========================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            tx_state      <= TX_IDLE;

            tx_shift_reg  <= '0;
            tx_bit_cnt    <= '0;
            tx_stop_cnt   <= '0;
            tx_parity_bit <= 1'b0;

            tx_serial_out <= 1'b1;
            tx_busy       <= 1'b0;
            tx_done       <= 1'b0;

        end
        else begin

            tx_state <= tx_next_state;

            // tx_done is a one-clock pulse.
            tx_done <= 1'b0;

            case (tx_state)

                //================================================
                // IDLE
                //================================================
                TX_IDLE: begin

                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;

                    if (tx_start) begin

                        tx_shift_reg <= tx_data;
                        tx_bit_cnt   <= '0;
                        tx_stop_cnt  <= '0;

                        tx_parity_bit <=
                            calc_parity(tx_data);

                        tx_busy <= 1'b1;

                    end

                end


                //================================================
                // START
                //================================================
                TX_START: begin

                    tx_busy       <= 1'b1;
                    tx_serial_out <= 1'b0;

                    if (baud_tick) begin

                        // First data bit starts immediately
                        // after the complete start-bit period.
                        tx_serial_out <= tx_shift_reg[0];

                    end

                end


                //================================================
                // DATA
                //================================================
                TX_DATA: begin

                    tx_busy <= 1'b1;

                    if (baud_tick) begin

                        if (tx_bit_cnt == DATA_LAST) begin

                            if (PARITY_MODE == "NONE") begin

                                tx_serial_out <= 1'b1;

                            end
                            else begin

                                tx_serial_out <= tx_parity_bit;

                            end

                        end
                        else begin

                            tx_bit_cnt <=
                                tx_bit_cnt + 1'b1;

                            tx_serial_out <=
                                tx_shift_reg[tx_bit_cnt + 1'b1];

                        end

                    end

                end


                //================================================
                // PARITY
                //================================================
                TX_PARITY: begin

                    tx_busy       <= 1'b1;
                    tx_serial_out <= tx_parity_bit;

                    if (baud_tick) begin
                        tx_serial_out <= 1'b1;
                        tx_stop_cnt   <= '0;
                    end

                end


                //================================================
                // STOP
                //================================================
                TX_STOP: begin

                    tx_busy       <= 1'b1;
                    tx_serial_out <= 1'b1;

                    if (baud_tick) begin

                        if (tx_stop_cnt == STOP_LAST) begin

                            tx_done <= 1'b1;

                        end
                        else begin

                            tx_stop_cnt <=
                                tx_stop_cnt + 1'b1;

                        end

                    end

                end


                //================================================
                // DONE
                //================================================
                TX_DONE: begin

                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;

                end


                //================================================
                // DEFAULT
                //================================================
                default: begin

                    tx_state      <= TX_IDLE;
                    tx_serial_out <= 1'b1;
                    tx_busy       <= 1'b0;

                end

            endcase

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
        RX_ERROR
    } rx_state_t;

    rx_state_t rx_state;
    rx_state_t rx_next_state;


    //============================================================
    // RX DATAPATH
    //============================================================
    logic [SAMPLE_CNT_W-1:0] rx_sample_cnt;

    logic [DATA_CNT_W-1:0] rx_bit_cnt;

    logic [STOP_CNT_W-1:0] rx_stop_cnt;

    logic [DATA_BITS-1:0] rx_shift_reg;

    logic rx_parity_accum;

    logic rx_parity_bad;

    logic rx_frame_bad;

    // Indicates rx_data contains an unread byte.
    logic rx_pending;


    //============================================================
    // RX NEXT STATE LOGIC
    //============================================================
    always_comb begin

        rx_next_state = rx_state;

        case (rx_state)

            //====================================================
            // IDLE
            //====================================================
            RX_IDLE: begin

                if (!rx_sync)
                    rx_next_state = RX_START_DETECT;

            end


            //====================================================
            // START DETECT
            //
            // Verify LOW at half-bit point.
            //====================================================
            RX_START_DETECT: begin

                if (sample_tick &&
                    (rx_sample_cnt == HALF_SAMPLE)) begin

                    if (rx_sync)
                        rx_next_state = RX_IDLE;
                    else
                        rx_next_state = RX_DATA;

                end

            end


            //====================================================
            // DATA
            //====================================================
            RX_DATA: begin

                if (sample_tick &&
                    (rx_sample_cnt == FULL_SAMPLE) &&
                    (rx_bit_cnt == DATA_LAST)) begin

                    if (PARITY_MODE == "NONE")
                        rx_next_state = RX_STOP;
                    else
                        rx_next_state = RX_PARITY;

                end

            end


            //====================================================
            // PARITY
            //====================================================
            RX_PARITY: begin

                if (sample_tick &&
                    (rx_sample_cnt == FULL_SAMPLE)) begin

                    rx_next_state = RX_STOP;

                end

            end


            //====================================================
            // STOP
            //====================================================
            RX_STOP: begin

                if (sample_tick &&
                    (rx_sample_cnt == FULL_SAMPLE) &&
                    (rx_stop_cnt == STOP_LAST)) begin

                    if (!rx_sync)
                        rx_next_state = RX_ERROR;
                    else if (rx_parity_bad)
                        rx_next_state = RX_ERROR;
                    else
                        rx_next_state = RX_IDLE;

                end

            end


            //====================================================
            // ERROR / DONE
            //====================================================
            RX_ERROR: begin

                rx_next_state = RX_IDLE;

            end


            //====================================================
            // DEFAULT
            //====================================================
            default: begin

                rx_next_state = RX_IDLE;

            end

        endcase

    end


    //============================================================
    // RX STATE REGISTER + DATAPATH + REGISTERED OUTPUTS
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            rx_state <= RX_IDLE;

            rx_sample_cnt <= '0;
            rx_bit_cnt    <= '0;
            rx_stop_cnt   <= '0;

            rx_shift_reg <= '0;
            rx_data      <= '0;

            rx_parity_accum <= 1'b0;
            rx_parity_bad   <= 1'b0;
            rx_frame_bad    <= 1'b0;

            rx_pending <= 1'b0;

            rx_valid      <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
            overrun_error <= 1'b0;

        end
        else begin

            rx_state <= rx_next_state;

            // Single-cycle pulse.
            rx_valid <= 1'b0;


            //====================================================
            // Consumer acknowledges previous byte.
            //====================================================
            if (rx_read)
                rx_pending <= 1'b0;


            //====================================================
            // Sampling datapath
            //====================================================
            if (sample_tick) begin

                case (rx_state)

                    //================================================
                    // IDLE
                    //================================================
                    RX_IDLE: begin

                        rx_sample_cnt <= '0;
                        rx_bit_cnt    <= '0;
                        rx_stop_cnt   <= '0;

                        rx_parity_accum <= 1'b0;
                        rx_parity_bad   <= 1'b0;
                        rx_frame_bad    <= 1'b0;

                    end


                    //================================================
                    // START DETECT
                    //================================================
                    RX_START_DETECT: begin

                        if (rx_sample_cnt == HALF_SAMPLE) begin

                            if (!rx_sync) begin

                                // Valid start bit.
                                rx_sample_cnt <= '0;
                                rx_bit_cnt    <= '0;

                            end
                            else begin

                                // Glitch rejected.
                                rx_sample_cnt <= '0;

                            end

                        end
                        else begin

                            rx_sample_cnt <=
                                rx_sample_cnt + 1'b1;

                        end

                    end


                    //================================================
                    // DATA
                    //================================================
                    RX_DATA: begin

                        if (rx_sample_cnt == FULL_SAMPLE) begin

                            // UART sends LSB first.
                            rx_shift_reg[rx_bit_cnt] <= rx_sync;

                            rx_parity_accum <=
                                rx_parity_accum ^ rx_sync;

                            rx_sample_cnt <= '0;

                            if (rx_bit_cnt != DATA_LAST) begin

                                rx_bit_cnt <=
                                    rx_bit_cnt + 1'b1;

                            end

                        end
                        else begin

                            rx_sample_cnt <=
                                rx_sample_cnt + 1'b1;

                        end

                    end


                    //================================================
                    // PARITY
                    //================================================
                    RX_PARITY: begin

                        if (rx_sample_cnt == FULL_SAMPLE) begin

                            if (PARITY_MODE == "ODD") begin

                                rx_parity_bad <=
                                    (rx_sync != ~rx_parity_accum);

                            end
                            else begin

                                rx_parity_bad <=
                                    (rx_sync != rx_parity_accum);

                            end

                            rx_sample_cnt <= '0;

                        end
                        else begin

                            rx_sample_cnt <=
                                rx_sample_cnt + 1'b1;

                        end

                    end


                    //================================================
                    // STOP
                    //================================================
                    RX_STOP: begin

                        if (rx_sample_cnt == FULL_SAMPLE) begin

                            //------------------------------------------------
                            // Invalid stop bit
                            //------------------------------------------------
                            if (!rx_sync) begin

                                framing_error <= 1'b1;
                                rx_frame_bad  <= 1'b1;

                            end


                            //------------------------------------------------
                            // Last stop bit
                            //------------------------------------------------
                            if (rx_stop_cnt == STOP_LAST) begin

                                if (rx_sync &&
                                    !rx_parity_bad &&
                                    !rx_frame_bad) begin

                                    //------------------------------------------------
                                    // Valid frame.
                                    //------------------------------------------------
                                    if (rx_pending) begin

                                        // Previous byte not consumed.
                                        overrun_error <= 1'b1;

                                    end
                                    else begin

                                        rx_data    <= rx_shift_reg;
                                        rx_valid   <= 1'b1;
                                        rx_pending <= 1'b1;

                                    end

                                end
                                else if (rx_parity_bad) begin

                                    parity_error <= 1'b1;

                                end

                                rx_stop_cnt <= '0;

                            end
                            else begin

                                rx_stop_cnt <=
                                    rx_stop_cnt + 1'b1;

                            end

                            rx_sample_cnt <= '0;

                        end
                        else begin

                            rx_sample_cnt <=
                                rx_sample_cnt + 1'b1;

                        end

                    end


                    //================================================
                    // ERROR / DONE
                    //================================================
                    RX_ERROR: begin

                        rx_sample_cnt <= '0;
                        rx_bit_cnt    <= '0;
                        rx_stop_cnt   <= '0;

                    end


                    //================================================
                    // DEFAULT
                    //================================================
                    default: begin

                        rx_state      <= RX_IDLE;
                        rx_sample_cnt <= '0;
                        rx_bit_cnt    <= '0;
                        rx_stop_cnt   <= '0;

                    end

                endcase

            end

        end

    end

endmodule
