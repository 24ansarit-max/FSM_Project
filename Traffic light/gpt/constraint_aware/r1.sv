
`timescale 1ns/1ps

module traffic_controller_4way #(
    parameter longint unsigned CLK_FREQ_HZ      = 100_000_000,
    parameter longint unsigned GREEN_TIME_SEC   = 10,
    parameter longint unsigned YELLOW_TIME_SEC  = 3,
    parameter longint unsigned ALL_RED_TIME_SEC = 1,
    parameter longint unsigned FAULT_FLASH_HZ   = 1
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       emergency_vehicle,
    input  logic       fault_detect,
    input  logic [3:0] pedestrian_request,

    output logic [2:0] light_N,
    output logic [2:0] light_E,
    output logic [2:0] light_S,
    output logic [2:0] light_W,
    output logic [3:0] pedestrian_walk,
    output logic [3:0] state_display
);

    // ------------------------------------------------
    // 1. FSM state definitions
    // Vivado may recode this FSM during synthesis.
    // ------------------------------------------------
    typedef enum logic [3:0] {
        N_Green      = 4'd0,
        N_Yellow     = 4'd1,
        E_Green      = 4'd2,
        E_Yellow     = 4'd3,
        S_Green      = 4'd4,
        S_Yellow     = 4'd5,
        W_Green      = 4'd6,
        W_Yellow     = 4'd7,
        All_Red      = 4'd8,
        Fault_Flash  = 4'd9
    } state_t;

    state_t state, next_state;

    // 0 = North, 1 = East, 2 = South, 3 = West.
    logic [1:0] next_approach;

    // ------------------------------------------------
    // 2. Asynchronous input synchronizers
    // ------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic emergency_meta;
    (* ASYNC_REG = "TRUE" *) logic emergency_sync;

    (* ASYNC_REG = "TRUE" *) logic fault_meta;
    (* ASYNC_REG = "TRUE" *) logic fault_sync;

    always_ff @(posedge clk) begin
        if (rst) begin
            emergency_meta <= 1'b0;
            emergency_sync <= 1'b0;
            fault_meta     <= 1'b0;
            fault_sync     <= 1'b0;
        end
        else begin
            emergency_meta <= emergency_vehicle;
            emergency_sync <= emergency_meta;

            fault_meta <= fault_detect;
            fault_sync <= fault_meta;
        end
    end

    // ------------------------------------------------
    // 3. Parameterized timer constants
    // ------------------------------------------------
    localparam longint unsigned GREEN_TICKS =
        CLK_FREQ_HZ * GREEN_TIME_SEC;

    localparam longint unsigned YELLOW_TICKS =
        CLK_FREQ_HZ * YELLOW_TIME_SEC;

    localparam longint unsigned ALL_RED_TICKS =
        CLK_FREQ_HZ * ALL_RED_TIME_SEC;

    localparam longint unsigned MAX_PHASE_TICKS =
        (GREEN_TICKS >= YELLOW_TICKS &&
         GREEN_TICKS >= ALL_RED_TICKS) ? GREEN_TICKS :
        (YELLOW_TICKS >= ALL_RED_TICKS) ? YELLOW_TICKS :
                                          ALL_RED_TICKS;

    localparam integer TIMER_WIDTH =
        (MAX_PHASE_TICKS <= 64'd1) ? 1 :
        $clog2(MAX_PHASE_TICKS);

    // Fault-flash timer: toggle red at twice the requested
    // blink frequency to create a full on/off blink cycle.
    localparam longint unsigned FLASH_HALF_TICKS =
        (CLK_FREQ_HZ / (64'd2 * FAULT_FLASH_HZ) < 64'd1)
        ? 64'd1
        : CLK_FREQ_HZ / (64'd2 * FAULT_FLASH_HZ);

    localparam integer FLASH_WIDTH =
        (FLASH_HALF_TICKS <= 64'd1) ? 1 :
        $clog2(FLASH_HALF_TICKS);

    logic [TIMER_WIDTH-1:0] timer;
    logic [FLASH_WIDTH-1:0] flash_timer;

    logic [63:0] phase_ticks;
    logic flash_on;

    // ------------------------------------------------
    // 4. Shared timer reload selection
    // ------------------------------------------------
    always_comb begin
        phase_ticks = ALL_RED_TICKS;

        case (state)
            N_Green, E_Green, S_Green, W_Green:
                phase_ticks = GREEN_TICKS;

            N_Yellow, E_Yellow, S_Yellow, W_Yellow:
                phase_ticks = YELLOW_TICKS;

            All_Red:
                phase_ticks = ALL_RED_TICKS;

            default:
                phase_ticks = ALL_RED_TICKS;
        endcase
    end

    // ------------------------------------------------
    // 5. State register and next-approach register
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= All_Red;
            next_approach <= 2'd0;
        end
        else begin
            state <= next_state;

            // Advance the remembered approach only when a
            // green phase naturally expires.
            if (!fault_sync && !emergency_sync) begin
                case (state)
                    N_Green:
                        if (timer >= GREEN_TICKS - 64'd1)
                            next_approach <= 2'd1;

                    E_Green:
                        if (timer >= GREEN_TICKS - 64'd1)
                            next_approach <= 2'd2;

                    S_Green:
                        if (timer >= GREEN_TICKS - 64'd1)
                            next_approach <= 2'd3;

                    W_Green:
                        if (timer >= GREEN_TICKS - 64'd1)
                            next_approach <= 2'd0;

                    default: ;
                endcase
            end
        end
    end

    // ------------------------------------------------
    // 6. Combinational next-state logic
    // ------------------------------------------------
    always_comb begin
        next_state = state;

        // Fault has priority over emergency and normal traffic.
        if (fault_sync) begin
            next_state = Fault_Flash;
        end
        else if (state == Fault_Flash) begin
            next_state = All_Red;
        end
        else if (emergency_sync) begin
            next_state = All_Red;
        end
        else begin
            case (state)
                N_Green:
                    if (timer >= GREEN_TICKS - 64'd1)
                        next_state = N_Yellow;

                N_Yellow:
                    if (timer >= YELLOW_TICKS - 64'd1)
                        next_state = All_Red;

                E_Green:
                    if (timer >= GREEN_TICKS - 64'd1)
                        next_state = E_Yellow;

                E_Yellow:
                    if (timer >= YELLOW_TICKS - 64'd1)
                        next_state = All_Red;

                S_Green:
                    if (timer >= GREEN_TICKS - 64'd1)
                        next_state = S_Yellow;

                S_Yellow:
                    if (timer >= YELLOW_TICKS - 64'd1)
                        next_state = All_Red;

                W_Green:
                    if (timer >= GREEN_TICKS - 64'd1)
                        next_state = W_Yellow;

                W_Yellow:
                    if (timer >= YELLOW_TICKS - 64'd1)
                        next_state = All_Red;

                All_Red:
                    if (timer >= ALL_RED_TICKS - 64'd1) begin
                        case (next_approach)
                            2'd0: next_state = N_Green;
                            2'd1: next_state = E_Green;
                            2'd2: next_state = S_Green;
                            2'd3: next_state = W_Green;
                            default: next_state = N_Green;
                        endcase
                    end

                default:
                    next_state = All_Red;
            endcase
        end
    end

    // ------------------------------------------------
    // 7. Single shared phase timer
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            timer <= '0;
        end
        else if (fault_sync || emergency_sync ||
                 state != next_state) begin
            timer <= '0;
        end
        else begin
            timer <= timer +
                {{(TIMER_WIDTH-1){1'b0}}, 1'b1};
        end
    end

    // ------------------------------------------------
    // 8. Fault-flash divider
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            flash_timer <= '0;
            flash_on    <= 1'b1;
        end
        else if (fault_sync || state == Fault_Flash) begin
            if (flash_timer >= FLASH_HALF_TICKS - 64'd1) begin
                flash_timer <= '0;
                flash_on    <= ~flash_on;
            end
            else begin
                flash_timer <= flash_timer +
                    {{(FLASH_WIDTH-1){1'b0}}, 1'b1};
            end
        end
        else begin
            flash_timer <= '0;
            flash_on    <= 1'b1;
        end
    end

    // ------------------------------------------------
    // 9. Output request decode
    // Requests are based on the state about to be entered,
    // so registered outputs follow state transitions together.
    // ------------------------------------------------
    logic req_N, req_E, req_S, req_W;
    logic yellow_N, yellow_E, yellow_S, yellow_W;

    logic grant_N, grant_E, grant_S, grant_W;

    always_comb begin
        req_N = 1'b0;
        req_E = 1'b0;
        req_S = 1'b0;
        req_W = 1'b0;

        yellow_N = 1'b0;
        yellow_E = 1'b0;
        yellow_S = 1'b0;
        yellow_W = 1'b0;

        case (next_state)
            N_Green:  req_N = 1'b1;
            N_Yellow: yellow_N = 1'b1;

            E_Green:  req_E = 1'b1;
            E_Yellow: yellow_E = 1'b1;

            S_Green:  req_S = 1'b1;
            S_Yellow: yellow_S = 1'b1;

            W_Green:  req_W = 1'b1;
            W_Yellow: yellow_W = 1'b1;

            default: ;
        endcase

        // Never request a green or yellow during an override.
        if (fault_sync || emergency_sync ||
            next_state == Fault_Flash) begin
            req_N = 1'b0;
            req_E = 1'b0;
            req_S = 1'b0;
            req_W = 1'b0;

            yellow_N = 1'b0;
            yellow_E = 1'b0;
            yellow_S = 1'b0;
            yellow_W = 1'b0;
        end
    end

    // ------------------------------------------------
    // 10. Final explicit mutual-exclusion interlock
    // ------------------------------------------------
    always_comb begin
        grant_N = req_N & ~req_E & ~req_S & ~req_W;
        grant_E = req_E & ~req_N & ~req_S & ~req_W;
        grant_S = req_S & ~req_N & ~req_E & ~req_W;
        grant_W = req_W & ~req_N & ~req_E & ~req_S;
    end

    // ------------------------------------------------
    // 11. Registered vehicle lights and pedestrian outputs
    // Light encoding: {Red, Yellow, Green}
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            light_N         <= 3'b100;
            light_E         <= 3'b100;
            light_S         <= 3'b100;
            light_W         <= 3'b100;
            pedestrian_walk <= 4'b0000;
        end
        else if (fault_sync || next_state == Fault_Flash) begin
            light_N <= {flash_on, 1'b0, 1'b0};
            light_E <= {flash_on, 1'b0, 1'b0};
            light_S <= {flash_on, 1'b0, 1'b0};
            light_W <= {flash_on, 1'b0, 1'b0};

            pedestrian_walk <= 4'b0000;
        end
        else if (emergency_sync) begin
            light_N <= 3'b100;
            light_E <= 3'b100;
            light_S <= 3'b100;
            light_W <= 3'b100;

            pedestrian_walk <= 4'b0000;
        end
        else begin
            // Final registered green outputs use interlocked grants.
            light_N <= {~(yellow_N | grant_N), yellow_N, grant_N};
            light_E <= {~(yellow_E | grant_E), yellow_E, grant_E};
            light_S <= {~(yellow_S | grant_S), yellow_S, grant_S};
            light_W <= {~(yellow_W | grant_W), yellow_W, grant_W};

            pedestrian_walk[0] <=
                pedestrian_request[0] & grant_N;
            pedestrian_walk[1] <=
                pedestrian_request[1] & grant_E;
            pedestrian_walk[2] <=
                pedestrian_request[2] & grant_S;
            pedestrian_walk[3] <=
                pedestrian_request[3] & grant_W;
        end
    end

    // ------------------------------------------------
    // 12. State display
    // ------------------------------------------------
    always_comb begin
        state_display = state;
    end

endmodule
