
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
    input  logic [3:0] pedestrian_request, // [0]=N,[1]=E,[2]=S,[3]=W

    output logic [2:0] light_N, // {Red, Yellow, Green}
    output logic [2:0] light_E,
    output logic [2:0] light_S,
    output logic [2:0] light_W,
    output logic [3:0] pedestrian_walk,
    output logic [3:0] current_state
);

    typedef enum logic [3:0] {
        N_Green     = 4'd0,
        N_Yellow    = 4'd1,
        E_Green     = 4'd2,
        E_Yellow    = 4'd3,
        S_Green     = 4'd4,
        S_Yellow    = 4'd5,
        W_Green     = 4'd6,
        W_Yellow    = 4'd7,
        All_Red     = 4'd8,
        Fault_Flash = 4'd9
    } state_t;

    state_t state;
    state_t next_normal_green;

    localparam longint unsigned GREEN_TICKS =
        CLK_FREQ_HZ * GREEN_TIME_SEC;

    localparam longint unsigned YELLOW_TICKS =
        CLK_FREQ_HZ * YELLOW_TIME_SEC;

    localparam longint unsigned ALL_RED_TICKS =
        CLK_FREQ_HZ * ALL_RED_TIME_SEC;

    localparam longint unsigned MAX_TICKS =
        (GREEN_TICKS >= YELLOW_TICKS &&
         GREEN_TICKS >= ALL_RED_TICKS) ? GREEN_TICKS :
        (YELLOW_TICKS >= ALL_RED_TICKS) ? YELLOW_TICKS :
                                          ALL_RED_TICKS;

    localparam integer TIMER_WIDTH =
        (MAX_TICKS <= 1) ? 1 : $clog2(MAX_TICKS);

    localparam longint unsigned FLASH_TICKS =
        (CLK_FREQ_HZ < 2) ? 1 : CLK_FREQ_HZ / 2;

    localparam integer FLASH_WIDTH =
        (FLASH_TICKS <= 1) ? 1 : $clog2(FLASH_TICKS);

    logic [TIMER_WIDTH-1:0] phase_count;
    logic [FLASH_WIDTH-1:0] flash_count;
    logic flash_red;

    logic emergency_prev;
    logic emergency_pending;
    logic emergency_serving;
    logic [1:0] emergency_target;

    // Return the next normal green state.
    function automatic state_t successor(input state_t s);
        case (s)
            N_Green: successor = E_Green;
            E_Green: successor = S_Green;
            S_Green: successor = W_Green;
            W_Green: successor = N_Green;
            default: successor = N_Green;
        endcase
    endfunction

    // ------------------------------------------------
    // Main FSM and phase timer
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state             <= All_Red;
            next_normal_green <= N_Green;
            phase_count       <= '0;

            emergency_prev    <= 1'b0;
            emergency_pending <= 1'b0;
            emergency_serving <= 1'b0;
            emergency_target  <= 2'b00;
        end
        else begin
            emergency_prev <= emergency_vehicle;

            // Capture the requested approach on a rising edge.
            if (emergency_vehicle && !emergency_prev) begin
                emergency_pending <= 1'b1;
                emergency_target  <= emergency_approach;
            end

            if (fault_detect) begin
                state             <= Fault_Flash;
                phase_count       <= '0;
                emergency_serving <= 1'b0;
                next_normal_green <= N_Green;
            end
            else if (state == Fault_Flash) begin
                state       <= All_Red;
                phase_count <= '0;
            end
            else if (emergency_vehicle && !emergency_prev) begin
                state       <= All_Red;
                phase_count <= '0;
            end
            else begin
                case (state)

                    N_Green, E_Green, S_Green, W_Green: begin
                        if (emergency_serving &&
                            !emergency_vehicle) begin
                            case (state)
                                N_Green: state <= N_Yellow;
                                E_Green: state <= E_Yellow;
                                S_Green: state <= S_Yellow;
                                W_Green: state <= W_Yellow;
                                default: state <= All_Red;
                            endcase
                            phase_count       <= '0;
                            emergency_serving <= 1'b0;
                        end
                        else if (emergency_serving) begin
                            // Hold the emergency approach green.
                            phase_count <= '0;
                        end
                        else if (phase_count >= GREEN_TICKS - 1) begin
                            case (state)
                                N_Green: state <= N_Yellow;
                                E_Green: state <= E_Yellow;
                                S_Green: state <= S_Yellow;
                                W_Green: state <= W_Yellow;
                                default: state <= All_Red;
                            endcase
                            phase_count <= '0;
                        end
                        else begin
                            phase_count <= phase_count + 1'b1;
                        end
                    end

                    N_Yellow, E_Yellow, S_Yellow, W_Yellow: begin
                        if (phase_count >= YELLOW_TICKS - 1) begin
                            case (state)
                                N_Yellow:
                                    next_normal_green <= E_Green;
                                E_Yellow:
                                    next_normal_green <= S_Green;
                                S_Yellow:
                                    next_normal_green <= W_Green;
                                W_Yellow:
                                    next_normal_green <= N_Green;
                                default:
                                    next_normal_green <= N_Green;
                            endcase

                            state       <= All_Red;
                            phase_count <= '0;
                        end
                        else begin
                            phase_count <= phase_count + 1'b1;
                        end
                    end

                    All_Red: begin
                        if (phase_count >= ALL_RED_TICKS - 1) begin
                            phase_count <= '0;

                            if (emergency_pending ||
                                emergency_vehicle) begin
                                case (emergency_target)
                                    2'b00: state <= N_Green;
                                    2'b01: state <= E_Green;
                                    2'b10: state <= S_Green;
                                    2'b11: state <= W_Green;
                                    default: state <= N_Green;
                                endcase

                                case (emergency_target)
                                    2'b00:
                                        next_normal_green <= E_Green;
                                    2'b01:
                                        next_normal_green <= S_Green;
                                    2'b10:
                                        next_normal_green <= W_Green;
                                    2'b11:
                                        next_normal_green <= N_Green;
                                    default:
                                        next_normal_green <= N_Green;
                                endcase

                                emergency_pending <= 1'b0;
                                emergency_serving <= 1'b1;
                            end
                            else begin
                                state <= next_normal_green;
                            end
                        end
                        else begin
                            phase_count <= phase_count + 1'b1;
                        end
                    end

                    default: begin
                        state       <= All_Red;
                        phase_count <= '0;
                    end

                endcase
            end
        end
    end

    // ------------------------------------------------
    // Fault flashing timer: toggle red every half-second
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            flash_count <= '0;
            flash_red   <= 1'b1;
        end
        else if (fault_detect || state == Fault_Flash) begin
            if (flash_count >= FLASH_TICKS - 1) begin
                flash_count <= '0;
                flash_red   <= ~flash_red;
            end
            else begin
                flash_count <= flash_count + 1'b1;
            end
        end
        else begin
            flash_count <= '0;
            flash_red   <= 1'b1;
        end
    end

    // ------------------------------------------------
    // Output decoder: defaults to all red.
    // ------------------------------------------------
    always_comb begin
        light_N         = 3'b100;
        light_E         = 3'b100;
        light_S         = 3'b100;
        light_W         = 3'b100;
        pedestrian_walk = 4'b0000;
        current_state   = state;

        if (fault_detect || state == Fault_Flash) begin
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
                N_Yellow: light_N = 3'b010;

                E_Green: begin
                    light_E = 3'b001;
                    pedestrian_walk[1] = pedestrian_request[1];
                end
                E_Yellow: light_E = 3'b010;

                S_Green: begin
                    light_S = 3'b001;
                    pedestrian_walk[2] = pedestrian_request[2];
                end
                S_Yellow: light_S = 3'b010;

                W_Green: begin
                    light_W = 3'b001;
                    pedestrian_walk[3] = pedestrian_request[3];
                end
                W_Yellow: light_W = 3'b010;

                All_Red: begin
                    // Default outputs are already all red.
                end

                default: begin
                    // Invalid state: remain all red.
                end
            endcase
        end
    end

endmodule
