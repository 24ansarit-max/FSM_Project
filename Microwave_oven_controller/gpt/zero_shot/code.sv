
module microwave_oven_controller (
    input clk,
    input reset,

    input       door_open,
    input       start_btn,
    input       pause_btn,
    input       timer_set_btn,
    input [7:0] timer_value,
    input       timer_done,

    output reg       magnetron_on,
    output reg       buzzer,
    output reg [7:0] display_time,
    output reg [2:0] state_led
);

    // ============================================================
    // State encoding
    // ============================================================
    localparam IDLE        = 3'b000;
    localparam DOOR_OPEN   = 3'b001;
    localparam DOOR_CLOSED = 3'b010;
    localparam TIMER_SET   = 3'b011;
    localparam RUNNING     = 3'b100;
    localparam PAUSED      = 3'b101;
    localparam DONE        = 3'b110;

    reg [2:0] state;
    reg [2:0] next_state;

    // Remaining cooking time
    reg [7:0] remaining_time;

    // ============================================================
    // State register and timer update logic
    // Synchronous active-high reset
    // ============================================================
    always @(posedge clk) begin
        if (reset) begin
            state          <= IDLE;
            remaining_time <= 8'd0;
        end
        else begin
            state <= next_state;

            case (state)

                // ------------------------------------------------
                // IDLE
                // Monitor the door.
                // No magnetron operation is allowed in IDLE.
                // ------------------------------------------------
                IDLE: begin
                    if (door_open) begin
                        remaining_time <= 8'd0;
                    end
                end

                // ------------------------------------------------
                // DOOR_OPEN
                // Operation is prohibited while door is open.
                // Time is preserved if the door was opened during
                // a cooking cycle.
                // ------------------------------------------------
                DOOR_OPEN: begin
                    // No countdown while door is open.
                end

                // ------------------------------------------------
                // DOOR_CLOSED
                // Door has been closed and machine can accept
                // a timer setting.
                // ------------------------------------------------
                DOOR_CLOSED: begin
                    if (timer_set_btn)
                        remaining_time <= timer_value;
                end

                // ------------------------------------------------
                // TIMER_SET
                // Store the selected cooking time.
                // ------------------------------------------------
                TIMER_SET: begin
                    if (timer_set_btn)
                        remaining_time <= timer_value;
                end

                // ------------------------------------------------
                // RUNNING
                // Countdown occurs only while the door is closed.
                // The next-state logic immediately sends the FSM
                // to DOOR_OPEN if door_open becomes active.
                // ------------------------------------------------
                RUNNING: begin
                    if (!door_open && !timer_done) begin
                        if (remaining_time > 0)
                            remaining_time <= remaining_time - 1'b1;
                    end
                end

                // ------------------------------------------------
                // PAUSED
                // Timer is halted. No countdown occurs.
                // ------------------------------------------------
                PAUSED: begin
                    // Timer remains unchanged.
                end

                // ------------------------------------------------
                // DONE
                // Cooking has completed.
                // ------------------------------------------------
                DONE: begin
                    remaining_time <= 8'd0;
                end

                default: begin
                    state          <= IDLE;
                    remaining_time <= 8'd0;
                end

            endcase
        end
    end

    // ============================================================
    // Next-state logic
    //
    // SAFETY INTERLOCK:
    // A door-open condition has priority over normal transitions.
    // Therefore RUNNING or PAUSED can never continue while the
    // door is open.
    // ============================================================
    always @(*) begin

        next_state = state;

        case (state)

            // ------------------------------------------------
            // IDLE
            // ------------------------------------------------
            IDLE: begin
                if (door_open)
                    next_state = DOOR_OPEN;
                else
                    next_state = DOOR_CLOSED;
            end

            // ------------------------------------------------
            // DOOR_OPEN
            //
            // The machine remains here until the door is
            // physically closed. It cannot start directly from
            // this state.
            // ------------------------------------------------
            DOOR_OPEN: begin
                if (!door_open)
                    next_state = DOOR_CLOSED;
                else
                    next_state = DOOR_OPEN;
            end

            // ------------------------------------------------
            // DOOR_CLOSED
            //
            // A timer must be set before entering RUNNING.
            // ------------------------------------------------
            DOOR_CLOSED: begin
                if (door_open)
                    next_state = DOOR_OPEN;
                else if (timer_set_btn)
                    next_state = TIMER_SET;
                else
                    next_state = DOOR_CLOSED;
            end

            // ------------------------------------------------
            // TIMER_SET
            //
            // Start is accepted only while the door is closed.
            // ------------------------------------------------
            TIMER_SET: begin
                if (door_open)
                    next_state = DOOR_OPEN;
                else if (start_btn && (remaining_time != 0))
                    next_state = RUNNING;
                else
                    next_state = TIMER_SET;
            end

            // ------------------------------------------------
            // RUNNING
            //
            // CRITICAL INTERLOCK:
            // door_open has priority over timer_done and all
            // other conditions. Thus an open door forces the FSM
            // to DOOR_OPEN on the next clock.
            // ------------------------------------------------
            RUNNING: begin
                if (door_open)
                    next_state = DOOR_OPEN;
                else if (timer_done || (remaining_time == 0))
                    next_state = DONE;
                else if (pause_btn)
                    next_state = PAUSED;
                else
                    next_state = RUNNING;
            end

            // ------------------------------------------------
            // PAUSED
            //
            // Magnetron remains off. The machine can resume only
            // when the door is still closed and start_btn is pressed.
            // ------------------------------------------------
            PAUSED: begin
                if (door_open)
                    next_state = DOOR_OPEN;
                else if (start_btn)
                    next_state = RUNNING;
                else
                    next_state = PAUSED;
            end

            // ------------------------------------------------
            // DONE
            //
            // Buzzer indicates completion. start_btn acts as the
            // acknowledgment and returns the controller to IDLE.
            // Door opening also returns to the safe DOOR_OPEN state.
            // ------------------------------------------------
            DONE: begin
                if (door_open)
                    next_state = DOOR_OPEN;
                else if (start_btn)
                    next_state = IDLE;
                else
                    next_state = DONE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    // ============================================================
    // Output logic
    //
    // CRITICAL HARD SAFETY INTERLOCK:
    // magnetron_on is explicitly gated with !door_open.
    //
    // Therefore, regardless of the FSM state, if door_open = 1,
    // magnetron_on is forced to 0.
    // ============================================================
    always @(*) begin

        // Safe default outputs
        magnetron_on = 1'b0;
        buzzer        = 1'b0;
        display_time  = remaining_time;
        state_led     = state;

        case (state)

            // ------------------------------------------------
            // IDLE: magnetron OFF
            // ------------------------------------------------
            IDLE: begin
                magnetron_on = 1'b0;
                buzzer        = 1'b0;
            end

            // ------------------------------------------------
            // DOOR_OPEN: magnetron MUST be OFF
            // ------------------------------------------------
            DOOR_OPEN: begin
                magnetron_on = 1'b0;
                buzzer        = 1'b0;
            end

            // ------------------------------------------------
            // DOOR_CLOSED: magnetron OFF
            // ------------------------------------------------
            DOOR_CLOSED: begin
                magnetron_on = 1'b0;
                buzzer        = 1'b0;
            end

            // ------------------------------------------------
            // TIMER_SET: magnetron OFF
            // ------------------------------------------------
            TIMER_SET: begin
                magnetron_on = 1'b0;
                buzzer        = 1'b0;
            end

            // ------------------------------------------------
            // RUNNING:
            // Magnetron is ON only when the door is closed.
            //
            // The !door_open condition is an additional safety
            // interlock independent of the FSM state.
            // ------------------------------------------------
            RUNNING: begin
                if (!door_open)
                    magnetron_on = 1'b1;
                else
                    magnetron_on = 1'b0;

                buzzer = 1'b0;
            end

            // ------------------------------------------------
            // PAUSED: magnetron MUST be OFF
            // ------------------------------------------------
            PAUSED: begin
                magnetron_on = 1'b0;
                buzzer        = 1'b0;
            end

            // ------------------------------------------------
            // DONE: magnetron OFF, buzzer ON
            // ------------------------------------------------
            DONE: begin
                magnetron_on = 1'b0;
                buzzer        = 1'b1;
            end

            default: begin
                magnetron_on = 1'b0;
                buzzer        = 1'b0;
            end

        endcase

        // --------------------------------------------------------
        // FINAL SAFETY OVERRIDE
        //
        // This condition has priority over every state output.
        // The magnetron can NEVER be asserted while the door is open.
        // --------------------------------------------------------
        if (door_open)
            magnetron_on = 1'b0;

    end

endmodule
