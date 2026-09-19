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
    output reg [7:0] display_time
);

    // State definitions
    localparam IDLE        = 3'b000;
    localparam DOOR_OPEN   = 3'b001;
    localparam DOOR_CLOSED = 3'b010;
    localparam TIMER_SET   = 3'b011;
    localparam RUNNING     = 3'b100;
    localparam PAUSED      = 3'b101;
    localparam DONE        = 3'b110;

    reg [2:0] state;
    reg [2:0] next_state;

    reg [7:0] remaining_time;

    // =========================================================
    // STATE REGISTER
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            state          <= IDLE;
            remaining_time <= 8'd0;
        end
        else begin

            // SAFETY ENFORCEMENT #1:
            // Door opening has highest priority and forces
            // the FSM into DOOR_OPEN.
            if (door_open) begin
                state <= DOOR_OPEN;
            end
            else begin
                state <= next_state;

                // Timer handling
                case (state)

                    DOOR_CLOSED: begin
                        if (timer_set_btn)
                            remaining_time <= timer_value;
                    end

                    TIMER_SET: begin
                        if (timer_set_btn)
                            remaining_time <= timer_value;
                    end

                    RUNNING: begin
                        if (!timer_done && remaining_time != 8'd0)
                            remaining_time <= remaining_time - 1'b1;
                    end

                    DONE: begin
                        remaining_time <= 8'd0;
                    end

                    default: begin
                        // Timer is preserved in other states,
                        // including PAUSED and DOOR_OPEN.
                    end

                endcase
            end
        end
    end

    // =========================================================
    // NEXT-STATE COMBINATIONAL LOGIC
    // =========================================================
    always @(*) begin

        // Default: remain in current state
        next_state = state;

        // SAFETY ENFORCEMENT #1:
        // door_open overrides all normal state transitions.
        if (door_open) begin
            next_state = DOOR_OPEN;
        end
        else begin

            case (state)

                IDLE: begin
                    if (door_open)
                        next_state = DOOR_OPEN;
                    else
                        next_state = DOOR_CLOSED;
                end

                DOOR_OPEN: begin
                    if (!door_open)
                        next_state = DOOR_CLOSED;
                    else
                        next_state = DOOR_OPEN;
                end

                DOOR_CLOSED: begin
                    if (timer_set_btn)
                        next_state = TIMER_SET;
                    else
                        next_state = DOOR_CLOSED;
                end

                TIMER_SET: begin
                    if (start_btn && (remaining_time != 8'd0))
                        next_state = RUNNING;
                    else
                        next_state = TIMER_SET;
                end

                RUNNING: begin
                    if (door_open)
                        next_state = DOOR_OPEN;
                    else if (pause_btn)
                        next_state = PAUSED;
                    else if (timer_done || (remaining_time == 8'd0))
                        next_state = DONE;
                    else
                        next_state = RUNNING;
                end

                PAUSED: begin
                    if (door_open)
                        next_state = DOOR_OPEN;
                    else if (start_btn)
                        next_state = RUNNING;
                    else
                        next_state = PAUSED;
                end

                DONE: begin
                    next_state = IDLE;
                end

                default: begin
                    next_state = IDLE;
                end

            endcase
        end
    end

    // =========================================================
    // OUTPUT LOGIC
    // =========================================================
    always @(*) begin

        magnetron_on = 1'b0;
        buzzer       = 1'b0;
        display_time = remaining_time;

        case (state)

            IDLE: begin
                magnetron_on = 1'b0;
                buzzer       = 1'b0;
            end

            DOOR_OPEN: begin
                magnetron_on = 1'b0;
                buzzer       = 1'b0;
            end

            DOOR_CLOSED: begin
                magnetron_on = 1'b0;
                buzzer       = 1'b0;
            end

            TIMER_SET: begin
                magnetron_on = 1'b0;
                buzzer       = 1'b0;
            end

            RUNNING: begin
                magnetron_on = 1'b1;
                buzzer       = 1'b0;
            end

            PAUSED: begin
                magnetron_on = 1'b0;
                buzzer       = 1'b0;
            end

            DONE: begin
                magnetron_on = 1'b0;
                buzzer       = 1'b1;
            end

            default: begin
                magnetron_on = 1'b0;
                buzzer       = 1'b0;
            end

        endcase

        // SAFETY ENFORCEMENT #2:
        // Independent output-level safety gate.
        // Magnetron can NEVER be active when door is open.
        if (door_open)
            magnetron_on = 1'b0;
    end

endmodule
