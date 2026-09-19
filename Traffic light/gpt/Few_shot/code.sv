module traffic_light_controller #(
    parameter RED_TIME    = 16'd32000,
    parameter GREEN_TIME  = 16'd28000,
    parameter YELLOW_TIME = 16'd5000
)(
    input clk,
    input reset,
    output reg red,
    output reg yellow,
    output reg green,
    output reg walk
);

    reg [1:0] state;
    reg [15:0] counter;

    parameter RED    = 2'b00;
    parameter GREEN  = 2'b01;
    parameter YELLOW = 2'b10;

    // State transitions and counter
    always @(posedge clk) begin
        if (reset) begin
            state   <= RED;
            counter <= RED_TIME - 1;
        end
        else begin
            case (state)
                RED: begin
                    if (counter == 0) begin
                        state   <= GREEN;
                        counter <= GREEN_TIME - 1;
                    end
                    else
                        counter <= counter - 1;
                end

                GREEN: begin
                    if (counter == 0) begin
                        state   <= YELLOW;
                        counter <= YELLOW_TIME - 1;
                    end
                    else
                        counter <= counter - 1;
                end

                YELLOW: begin
                    if (counter == 0) begin
                        state   <= RED;
                        counter <= RED_TIME - 1;
                    end
                    else
                        counter <= counter - 1;
                end

                default: begin
                    state   <= RED;
                    counter <= RED_TIME - 1;
                end
            endcase
        end
    end

    // Output logic
    always @(*) begin
        red    = 1'b0;
        yellow = 1'b0;
        green  = 1'b0;
        walk   = 1'b0;

        case (state)
            RED: begin
                red  = 1'b1;
                walk = 1'b1;
            end

            GREEN: begin
                green = 1'b1;
            end

            YELLOW: begin
                yellow = 1'b1;
            end

            default: begin
                red  = 1'b1;
                walk = 1'b1;
            end
        endcase
    end

endmodule
