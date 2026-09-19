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

    reg [1:0] state;
    reg [31:0] counter;

    // State and counter update logic
    always @(posedge clk) begin
        if (reset) begin
            state   <= RED;
            counter <= 0;
        end
        else begin
            case (state)

                // RED -> GREEN after RED_TIME clock cycles
                RED: begin
                    if (counter == RED_TIME - 1) begin
                        counter <= 0;
                        state   <= GREEN;
                    end
                    else begin
                        counter <= counter + 1;
                    end
                end

                // GREEN -> YELLOW after GREEN_TIME clock cycles
                GREEN: begin
                    if (counter == GREEN_TIME - 1) begin
                        counter <= 0;
                        state   <= YELLOW;
                    end
                    else begin
                        counter <= counter + 1;
                    end
                end

                // YELLOW -> RED after YELLOW_TIME clock cycles
                YELLOW: begin
                    if (counter == YELLOW_TIME - 1) begin
                        counter <= 0;
                        state   <= RED;
                    end
                    else begin
                        counter <= counter + 1;
                    end
                end

                // Recover to RED if an invalid state occurs
                default: begin
                    state   <= RED;
                    counter <= 0;
                end

            endcase
        end
    end

    // Output logic based on current FSM state
    always @(*) begin
        // Default outputs
        red       = 1'b0;
        yellow    = 1'b0;
        green     = 1'b0;
        walk      = 1'b0;
        dont_walk = 1'b1;

        case (state)

            // RED state: red light ON and pedestrian WALK allowed
            RED: begin
                red       = 1'b1;
                walk      = 1'b1;
                dont_walk = 1'b0;
            end

            // GREEN state: green light ON
            GREEN: begin
                green     = 1'b1;
                walk      = 1'b0;
                dont_walk = 1'b1;
            end

            // YELLOW state: yellow light ON
            YELLOW: begin
                yellow    = 1'b1;
                walk      = 1'b0;
                dont_walk = 1'b1;
            end

            // Safe default
            default: begin
                red       = 1'b1;
                walk      = 1'b1;
                dont_walk = 1'b0;
            end

        endcase
    end

endmodule
