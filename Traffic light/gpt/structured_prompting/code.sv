module traffic_light_controller #(
    parameter RED_TIME    = 5,
    parameter GREEN_TIME  = 5,
    parameter YELLOW_TIME = 2
)(
    input clk,
    input reset,

    output reg red,
    output reg yellow,
    output reg green,
    output reg walk,
    output reg dont_walk
);

    // State encoding
    localparam RED    = 2'b00;
    localparam GREEN  = 2'b01;
    localparam YELLOW = 2'b10;

    // State register and duration counter
    reg [1:0]  state;
    reg [31:0] counter;

    // State transition and counter logic
    always @(posedge clk) begin
        if (reset) begin
            // Synchronous active-high reset
            state   <= RED;
            counter <= 0;
        end
        else begin
            case (state)

                // RED -> GREEN
                RED: begin
                    if (counter >= RED_TIME - 1) begin
                        counter <= 0;
                        state   <= GREEN;
                    end
                    else begin
                        counter <= counter + 1;
                    end
                end

                // GREEN -> YELLOW
                GREEN: begin
                    if (counter >= GREEN_TIME - 1) begin
                        counter <= 0;
                        state   <= YELLOW;
                    end
                    else begin
                        counter <= counter + 1;
                    end
                end

                // YELLOW -> RED
                YELLOW: begin
                    if (counter >= YELLOW_TIME - 1) begin
                        counter <= 0;
                        state   <= RED;
                    end
                    else begin
                        counter <= counter + 1;
                    end
                end

                // Safe recovery from an invalid state
                default: begin
                    state   <= RED;
                    counter <= 0;
                end

            endcase
        end
    end

    // Output logic based on the current state
    always @(*) begin

        // Default outputs
        red       = 1'b0;
        yellow    = 1'b0;
        green     = 1'b0;
        walk      = 1'b0;
        dont_walk = 1'b1;

        case (state)

            // RED: Red light ON, pedestrian WALK
            RED: begin
                red       = 1'b1;
                walk      = 1'b1;
                dont_walk = 1'b0;
            end

            // GREEN: Green light ON, pedestrian DON'T WALK
            GREEN: begin
                green     = 1'b1;
                walk      = 1'b0;
                dont_walk = 1'b1;
            end

            // YELLOW: Yellow light ON, pedestrian DON'T WALK
            YELLOW: begin
                yellow    = 1'b1;
                walk      = 1'b0;
                dont_walk = 1'b1;
            end

            // Safe default output
            default: begin
                red       = 1'b1;
                walk      = 1'b1;
                dont_walk = 1'b0;
            end

        endcase
    end

endmodule
