module microwave_oven_controller (
    input clk,
    input reset,
    input door_open,
    input start_btn,
    input pause_btn,
    input timer_set_btn,
    input [7:0] timer_value_in,
    input tick_1s,

    output reg magnetron_on,
    output reg buzzer,
    output reg [7:0] display_time
);

    // State definitions
    localparam IDLE         = 3'b000;
    localparam DOOR_OPEN_ST = 3'b001;
    localparam DOOR_CLOSED  = 3'b010;
    localparam TIMER_SET    = 3'b011;
    localparam RUNNING      = 3'b100;
    localparam PAUSED       = 3'b101;
    localparam DONE         = 3'b110;

    reg [2:0] state;
    reg [2:0] next_state;

    // State register and timer register
    always @(posedge clk) begin
        if (reset) begin
            state        <= IDLE;
            display_time <= 8'd0;
        end
        else begin
            state <= next_state;

            // Load timer value when requested
            if (state == DOOR_CLOSED && timer_set_btn) begin
                display_time <= timer_value_in;
            end

            // Countdown only while running
            else if (state == RUNNING && tick_1s &&
                     display_time != 8'd0) begin
                display_time <= display_time - 1'b1;
            end

            // Clear timer when operation is complete
            else if (state == DONE) begin
                display_time <= 8'd0;
            end
        end
    end

    // Next-state combinational logic
    always @(*) begin

        // Default: remain in current state
        next_state = state;

        // SAFETY:
        // door_open has highest priority and unconditionally
        // forces the FSM to the safe DOOR_OPEN_ST state.
        if (door_open) begin
            next_state = DOOR_OPEN_ST;
        end
        else begin
            case (state)

                IDLE: begin
                    if (!door_open)
                        next_state = DOOR_CLOSED;
                    else
                        next_state = DOOR_OPEN_ST;
                end

                DOOR_OPEN_ST: begin
                    if (door_open)
                        next_state = DOOR_OPEN_ST;
                    else
                        next_state = DOOR_CLOSED;
                end

                DOOR_CLOSED: begin
                    if (timer_set_btn)
                        next_state = TIMER_SET;
                    else
                        next_state = DOOR_CLOSED;
                end

                TIMER_SET: begin
                    if (start_btn && !door_open)
                        next_state = RUNNING;
                    else
                        next_state = TIMER_SET;
                end

                RUNNING: begin
                    if (door_open)
                        next_state = DOOR_OPEN_ST;
                    else if (pause_btn)
                        next_state = PAUSED;
                    else if (display_time == 8'd0)
                        next_state = DONE;
                    else
                        next_state = RUNNING;
                end

                PAUSED: begin
                    if (start_btn && !door_open)
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

    // Output combinational logic
    always @(*) begin
        buzzer = 1'b0;

        case (state)

            IDLE: begin
                buzzer = 1'b0;
            end

            DOOR_OPEN_ST: begin
                buzzer = 1'b0;
            end

            DOOR_CLOSED: begin
                buzzer = 1'b0;
            end

            TIMER_SET: begin
                buzzer = 1'b0;
            end

            RUNNING: begin
                buzzer = 1'b0;
            end

            PAUSED: begin
                buzzer = 1'b0;
            end

            DONE: begin
                buzzer = 1'b1;
            end

            default: begin
                buzzer = 1'b0;
            end

        endcase

        // SAFETY:
        // Independent output-level safety override.
        // Magnetron is allowed ONLY when the state is RUNNING
        // AND the door is closed.
        magnetron_on = (state == RUNNING) && !door_open;
    end

endmodule
