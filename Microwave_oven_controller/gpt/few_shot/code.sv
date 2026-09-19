module microwave_oven_controller (
    input clk,
    input reset,
    input door_open,
    input start_btn,
    input pause_btn,
    input timer_set_btn,
    input [7:0] timer_value,
    input timer_done,

    output reg magnetron_on,
    output reg buzzer,
    output reg [7:0] display_time
);

    localparam IDLE        = 3'b000;
    localparam DOOR_OPEN   = 3'b001;
    localparam DOOR_CLOSED = 3'b010;
    localparam TIMER_SET   = 3'b011;
    localparam RUNNING     = 3'b100;
    localparam PAUSED      = 3'b101;
    localparam DONE        = 3'b110;

    reg [2:0] state;
    reg [7:0] remaining_time;

    // State register with critical safety override.
    always @(posedge clk) begin
        if (reset) begin
            state          <= IDLE;
            remaining_time <= 8'd0;
        end
        else if (door_open) begin
            // Door open always forces the oven to a safe state.
            state <= DOOR_OPEN;
        end
        else begin
            case (state)

                IDLE: begin
                    state <= DOOR_CLOSED;
                end

                DOOR_OPEN: begin
                    // Door must be closed before normal operation.
                    state <= DOOR_CLOSED;
                end

                DOOR_CLOSED: begin
                    if (timer_set_btn) begin
                        remaining_time <= timer_value;
                        state <= TIMER_SET;
                    end
                    else begin
                        state <= DOOR_CLOSED;
                    end
                end

                TIMER_SET: begin
                    if (timer_set_btn)
                        remaining_time <= timer_value;

                    if (start_btn && (remaining_time != 8'd0))
                        state <= RUNNING;
                    else
                        state <= TIMER_SET;
                end

                RUNNING: begin
                    if (pause_btn)
                        state <= PAUSED;
                    else if (timer_done || (remaining_time == 8'd0))
                        state <= DONE;
                    else begin
                        if (remaining_time > 8'd0)
                            remaining_time <= remaining_time - 1'b1;

                        state <= RUNNING;
                    end
                end

                PAUSED: begin
                    // Timer remains unchanged while paused.
                    if (start_btn)
                        state <= RUNNING;
                    else
                        state <= PAUSED;
                end

                DONE: begin
                    remaining_time <= 8'd0;
                    state <= IDLE;
                end

                default: begin
                    state          <= IDLE;
                    remaining_time <= 8'd0;
                end

            endcase
        end
    end

    // Outputs with independent safety gating.
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

        // SECOND SAFETY LAYER:
        // Magnetron can never be ON while the door is open.
        if (door_open)
            magnetron_on = 1'b0;
    end

endmodule
