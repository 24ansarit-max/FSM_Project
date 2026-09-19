module traffic_light_controller #(
    parameter RED_TIME    = 16'd32000,
    parameter GREEN_TIME  = 16'd28000,
    parameter YELLOW_TIME = 16'd5000
)(
    input  wire clk,
    input  wire reset,

    output reg red,
    output reg yellow,
    output reg green,

    output reg walk,
    output reg dont_walk
);

    // FSM state encoding
    localparam RED    = 2'b00;
    localparam GREEN  = 2'b01;
    localparam YELLOW = 2'b10;

    reg [1:0] state;
    reg [15:0] counter;

    // Synchronous active-high reset
    always @(posedge clk) begin

        if (reset) begin
            state   <= RED;
            counter <= RED_TIME - 1'b1;
        end

        else begin

            case (state)

                // ------------------------------------------------
                // RED state
                // ------------------------------------------------
                RED: begin
                    if (counter == 16'd0) begin
                        state   <= GREEN;
                        counter <= GREEN_TIME - 1'b1;
                    end
                    else begin
                        counter <= counter - 1'b1;
                    end
                end

                // ------------------------------------------------
                // GREEN state
                // ------------------------------------------------
                GREEN: begin
                    if (counter == 16'd0) begin
                        state   <= YELLOW;
                        counter <= YELLOW_TIME - 1'b1;
                    end
                    else begin
                        counter <= counter - 1'b1;
                    end
                end

                // ------------------------------------------------
                // YELLOW state
                // ------------------------------------------------
                YELLOW: begin
                    if (counter == 16'd0) begin
                        state   <= RED;
                        counter <= RED_TIME - 1'b1;
                    end
                    else begin
                        counter <= counter - 1'b1;
                    end
                end

                // ------------------------------------------------
                // Safety recovery
                // ------------------------------------------------
                default: begin
                    state   <= RED;
                    counter <= RED_TIME - 1'b1;
                end

            endcase
        end
    end

    // Output decoder
    always @(*) begin

        // Default outputs
        red       = 1'b0;
        yellow    = 1'b0;
        green     = 1'b0;
        walk      = 1'b0;
        dont_walk = 1'b1;

        case (state)

            RED: begin
                red       = 1'b1;
                walk      = 1'b1;
                dont_walk = 1'b0;
            end

            GREEN: begin
                green     = 1'b1;
                walk      = 1'b0;
                dont_walk = 1'b1;
            end

            YELLOW: begin
                yellow    = 1'b1;
                walk      = 1'b0;
                dont_walk = 1'b1;
            end

            default: begin
                red       = 1'b1;
                walk      = 1'b1;
                dont_walk = 1'b0;
            end

        endcase
    end

endmodule
