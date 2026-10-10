
`timescale 1ns/1ps

module traffic_controller_4way #(
    parameter longint unsigned CLK_FREQ_HZ      = 50_000_000,
    parameter longint unsigned GREEN_TIME_SEC   = 10,
    parameter longint unsigned YELLOW_TIME_SEC  = 3,
    parameter longint unsigned ALL_RED_TIME_SEC = 1
)(
    input  logic       clk,
    input  logic       rst,

    input  logic       emergency_vehicle,
    input  logic [1:0] emergency_approach, // 00=N, 01=E, 10=S, 11=W
    input  logic       fault_detect,
    input  logic [3:0] pedestrian_request, // N, E, S, W

    output logic [2:0] light_N, // {Red, Yellow, Green}
    output logic [2:0] light_E,
    output logic [2:0] light_S,
    output logic [2:0] light_W,

    output logic [3:0] pedestrian_walk,
    output logic [3:0] current_state
);

    // State encoding for display/debugging.
    typedef enum logic [3:0] {
        N_Green   = 4'd0,
        N_Yellow  = 4'd1,
        E_Green   = 4'd2,
        E_Yellow  = 4'd3,
        S_Green   = 4'd4,
        S_Yellow  = 4'd5,
        W_Green   = 4'd6,
        W_Yellow  = 4'd7,
        All_Red   = 4'd8,
        Fault_Flash = 4'd9
    } state_t;

    state_t state, next_normal_green;

    localparam longint unsigned GREEN_TICKS =
        CLK_FREQ_HZ * GREEN_TIME_SEC;

    localparam longint unsigned YELLOW_TICKS =
        CLK_FREQ_HZ * YELLOW_TIME_SEC;

    localparam longint unsigned ALL_RED_TICKS =
        CLK_FREQ_HZ * ALL_RED_TIME_SEC;

    localparam longint unsigned MAX_PHASE_TICKS =
        (GREEN_TICKS > YELLOW_TICKS)
            ? ((GREEN_TICKS > ALL_RED_TICKS)
                ? GREEN_TICKS : ALL_RED_TICKS)
            : ((YELLOW_TICKS > ALL_RED_TICKS)
                ? YELLOW_TICKS : ALL_RED_TICKS);

    localparam integer TIMER_WIDTH =
        (MAX_PHASE_TICKS <= 1) ? 1 : $clog2(MAX_PHASE_TICKS);

    // Half-second counter for fault flashing.
    localparam longint unsigned FLASH_HALF_TICKS =
        (CLK_FREQ_HZ < 2) ? 1 : CLK_FREQ_HZ / 2;

    localparam integer FLASH_WIDTH =
        (FLASH_HALF_TICKS <= 1)
            ? 1 : $clog2(FLASH_HALF_TICKS);

    logic [TIMER_WIDTH-1:0] phase_count;
    logic [FLASH_WIDTH-1:0] flash_count;
    logic flash_red;

    logic emergency_prev;
    logic emergency_pending;
    logic [1:0] emergency_target;

    // -------------------------------------------------
    // Sequential FSM and phase timer
    // -------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state              <= All_Red;
            next_normal_green  <= N_Green;
            phase_count        <= '0;
            emergency_prev     <= 1'b0;
            emergency_pending  <= 1'b0;
            emergency_target   <= 2'b00;
        end
        else begin
            emergency_prev <= emergency_vehicle;

            // Latch each new emergency request.
            // Fault detection always has higher priority.
            if (emergency_vehicle && !emergency_prev) begin
                emergency_pending <= 1'b1;
                emergency_target  <= emergency_approach;
            end

            if (fault_detect) begin
                state       <= Fault_Flash;
                phase_count <= '0;
            end
            else if (state == Fault_Flash) begin
                // Exit fault mode safely through all-red.
                state       <= All_Red;
                phase_count <= '0;
            end
            else if (emergency_vehicle && !emergency_prev) begin
                // Immediately remove all green outputs.
                state       <= All_Red;
                phase_count <= '0;
            end
            else begin
                case (state)

                    N_Green: begin
                        if (phase_count >= GREEN_TICKS - 1) begin
                            state       <= N_Yellow;
                            phase_count <= '0;
                        end
                        else
                            phase_count <= phase_count + 1'b1;
                    end

                    N_Yellow: begin
                        if (phase_count >= YELLOW_TICKS - 1) begin
                            next_normal_green <= E_Green;
                            state             <= All_Red;
                            phase_count       <= '0;
                        end
                        else
                            phase_count <= phase_count + 1'b1;
                    end

                    E_Green: begin
                        if (phase_count >= GREEN_TICKS - 1) begin
                            state       <= E_Yellow;
                            phase_count <= '0;
                        end
                        else
                            phase_count <= phase_count + 1'b1;
                    end

                    E_Yellow: begin
                        if (phase_count >= YELLOW_TICKS - 1) begin
                            next_normal_green <= S_Green;
                            state             <= All_Red;
                            phase_count       <= '0;
                        end
                        else
                            phase_count <= phase_count + 1'b1;
                    end

                    S_Green: begin
                        if (phase_count >= GREEN_TICKS - 1) begin
                            state       <= S_Yellow;
                            phase_count <= '0;
                        end
                        else
                            phase_count <= phase_count + 1'b1;
                    end

                    S_Yellow: begin
                        if (phase_count >= YELLOW_TICKS - 1) begin
                            next_normal_green <= W_Green;
                            state             <= All_Red;
                            phase_count       <= '0;
                        end
                        else
                            phase_count <= phase_count + 1'b1;
                    end

                    W_Green: begin
                        if (phase_count >= GREEN_TICKS - 1) begin
                            state       <= W_Yellow;
                            phase_count <= '0;
                        end
                        else
                            phase_count <= phase_count + 1'b1;
                    end

                    W_Yellow: begin
                        if (phase_count >= YELLOW_TICKS - 1) begin
                            next_normal_green <= N_Green;
                            state             <= All_Red;
                            phase_count       <= '0;
                        end
                        else
                            phase_count <= phase_count + 1'b1;
                    end

                    All_Red: begin
                        if (phase_count >= ALL_RED_TICKS - 1) begin
                            phase_count <= '0;

                            if (emergency_pending) begin
                                // Serve the requested emergency approach.
                                case (emergency_target)
                                    2'b00: state <= N_Green;
                                    2'b01: state <= E_Green;
                                    2'b10: state <= S_Green;
                                    2'b11: state <= W_Green;
                                    default: state <= N_Green;
                                endcase

                                emergency_pending <= 1'b0;
                            end
                            else begin
                                state <= next_normal_green;
                            end
                        end
                        else
                            phase_count <= phase_count + 1'b1;
                    end

                    default: begin
                        state       <= All_Red;
                        phase_count <= '0;
                    end

                endcase
            end
        end
    end

    // -------------------------------------------------
    // Fault mode: flash red on all approaches.
    // This timer is independent of the phase timer.
    // -------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            flash_count <= '0;
            flash_red   <= 1'b0;
        end
        else if (fault_detect || state == Fault_Flash) begin
            if (flash_count >= FLASH_HALF_TICKS - 1) begin
                flash_count <= '0;
                flash_red   <= ~flash_red;
            end
            else begin
                flash_count <= flash_count + 1'b1;
            end
        end
        else begin
            flash_count <= '0;
            flash_red   <= 1'b0;
        end
    end

    // -------------------------------------------------
    // Combinational outputs.
    // Default is ALL RED, providing a fail-safe output.
    // Encoding: {R,Y,G}
    // RED    = 3'b100
    // YELLOW = 3'b010
    // GREEN  = 3'b001
    // -------------------------------------------------
    always_comb begin
        light_N        = 3'b100;
        light_E        = 3'b100;
        light_S        = 3'b100;
        light_W        = 3'b100;
        pedestrian_walk = 4'b0000;

        current_state = state;

        if (fault_detect || state == Fault_Flash) begin
            // All approaches flash red together.
            light_N = flash_red ? 3'b100 : 3'b000;
            light_E = flash_red ? 3'b100 : 3'b000;
            light_S = flash_red ? 3'b100 : 3'b000;
            light_W = flash_red ? 3'b100 : 3'b000;
        end
        else begin
            case (state)

                N_Green: begin
                    light_N = 3'b001;
                    pedestrian_walk[0] = pedestrian_request[0];
                end

                N_Yellow: begin
                    light_N = 3'b010;
                end

                E_Green: begin
                    light_E = 3'b001;
                    pedestrian_walk[1] = pedestrian_request[1];
                end

                E_Yellow: begin
                    light_E = 3'b010;
                end

                S_Green: begin
                    light_S = 3'b001;
                    pedestrian_walk[2] = pedestrian_request[2];
                end

                S_Yellow: begin
                    light_S = 3'b010;
                end

                W_Green: begin
                    light_W = 3'b001;
                    pedestrian_walk[3] = pedestrian_request[3];
                end

                W_Yellow: begin
                    light_W = 3'b010;
                end

                All_Red: begin
                    // Default outputs already set to all red.
                end

                default: begin
                    // Unknown/invalid state: all red.
                end

            endcase
        end
    end

endmodule
