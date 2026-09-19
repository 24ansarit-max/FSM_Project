module traffic_light_controller (
    input  wire clk,
    input  wire reset,

    output reg red,
    output reg yellow,
    output reg green,

    output reg walk,
    output reg dont_walk
);

    // State encoding
    parameter RED    = 2'b00;
    parameter GREEN  = 2'b01;
    parameter YELLOW = 2'b10;

    reg [1:0] state;
    reg [2:0] count;

    // State durations
    parameter RED_TIME    = 3'd5;
    parameter GREEN_TIME  = 3'd5;
    parameter YELLOW_TIME = 3'd2;

    // Single clocked behavioral block
    always @(posedge clk) begin

        // Synchronous reset
        if (reset) begin
            state <= RED;
            count <= 3'd0;

            red      <= 1'b1;
            yellow   <= 1'b0;
            green    <= 1'b0;
            walk     <= 1'b1;
            dont_walk <= 1'b0;
        end

        else begin

            case (state)

                // ---------------- RED STATE ----------------
                RED: begin
                    red       <= 1'b1;
                    yellow    <= 1'b0;
                    green     <= 1'b0;
                    walk      <= 1'b1;
                    dont_walk <= 1'b0;

                    if (count == RED_TIME - 1) begin
                        count <= 3'd0;
                        state <= GREEN;
                    end
                    else begin
                        count <= count + 1'b1;
                    end
                end

                // ---------------- GREEN STATE ----------------
                GREEN: begin
                    red       <= 1'b0;
                    yellow    <= 1'b0;
                    green     <= 1'b1;
                    walk      <= 1'b0;
                    dont_walk <= 1'b1;

                    if (count == GREEN_TIME - 1) begin
                        count <= 3'd0;
                        state <= YELLOW;
                    end
                    else begin
                        count <= count + 1'b1;
                    end
                end

                // ---------------- YELLOW STATE ----------------
                YELLOW: begin
                    red       <= 1'b0;
                    yellow    <= 1'b1;
                    green     <= 1'b0;
                    walk      <= 1'b0;
                    dont_walk <= 1'b1;

                    if (count == YELLOW_TIME - 1) begin
                        count <= 3'd0;
                        state <= RED;
                    end
                    else begin
                        count <= count + 1'b1;
                    end
                end

                // ---------------- DEFAULT ----------------
                default: begin
                    state <= RED;
                    count <= 3'd0;

                    red       <= 1'b1;
                    yellow    <= 1'b0;
                    green     <= 1'b0;
                    walk      <= 1'b1;
                    dont_walk <= 1'b0;
                end

            endcase
        end
    end

endmodule
