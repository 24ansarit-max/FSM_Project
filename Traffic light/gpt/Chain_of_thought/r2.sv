
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
    input  logic       fault_detect,
    input  logic [3:0] pedestrian_request,

    output logic [2:0] light_N,
    output logic [2:0] light_E,
    output logic [2:0] light_S,
    output logic [2:0] light_W,
    output logic [3:0] pedestrian_walk,
    output logic [3:0] state_display
);

    // State encoding
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

    state_t state, next_state;
    state_t next_green;

    // Convert phase durations into clock cycles.
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

    // Fault red-flash half-period.
    localparam longint unsigned FLASH_TICKS =
        (CLK_FREQ_HZ < 2) ? 1 : CLK_FREQ_HZ / 2;

    localparam integer FLASH_WIDTH =
        (FLASH_TICKS <= 1) ? 1 : $clog2(FLASH_TICKS);

    logic [TIMER_WIDTH-1:0] timer;
    logic [FLASH_WIDTH-1:0] flash_timer;
    logic flash_on;

    logic req_N, req_E, req_S, req_W;
    logic grant_N, grant_E, grant_S, grant_W;
    logic yellow_N, yellow_E, yellow_S, yellow_W;

    // ------------------------------------------------
    // 1. Sequential FSM, phase timer and next approach
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= All_Red;
            next_green <= N_Green;
            timer      <= '0;
        end
        else begin
            state <= next_state;

            if (fault_detect || emergency_vehicle ||
                state != next_state)
                timer <= '0;
            else
                timer <= timer + 1'b1;

            // Remember the next approach when the current
            // green phase expires.
            if (!fault_detect && !emergency_vehicle) begin
                case (state)
                    N_Green:
                        if (timer >= GREEN_TICKS - 1)
                            next_green <= E_Green;

                    E_Green:
                        if (timer >= GREEN_TICKS - 1)
                            next_green <= S_Green;

                    S_Green:
                        if (timer >= GREEN_TICKS - 1)
                            next_green <= W_Green;

                    W_Green:
                        if (timer >= GREEN_TICKS - 1)
                            next_green <= N_Green;

                    default: ;
                endcase
            end
        end
    end

    // ------------------------------------------------
    // 2. Combinational next-state logic
    // ------------------------------------------------
    always_comb begin
        next_state = state;

        if (fault_detect) begin
            next_state = Fault_Flash;
        end
        else if (state == Fault_Flash) begin
            next_state = All_Red;
        end
        else if (emergency_vehicle) begin
            next_state = All_Red;
        end
        else begin
            case (state)
                N_Green:
                    if (timer >= GREEN_TICKS - 1)
                        next_state = N_Yellow;

                N_Yellow:
                    if (timer >= YELLOW_TICKS - 1)
                        next_state = All_Red;

                E_Green:
                    if (timer >= GREEN_TICKS - 1)
                        next_state = E_Yellow;

                E_Yellow:
                    if (timer >= YELLOW_TICKS - 1)
                        next_state = All_Red;

                S_Green:
                    if (timer >= GREEN_TICKS - 1)
                        next_state = S_Yellow;

                S_Yellow:
                    if (timer >= YELLOW_TICKS - 1)
                        next_state = All_Red;

                W_Green:
                    if (timer >= GREEN_TICKS - 1)
                        next_state = W_Yellow;

                W_Yellow:
                    if (timer >= YELLOW_TICKS - 1)
                        next_state = All_Red;

                All_Red:
                    if (timer >= ALL_RED_TICKS - 1)
                        next_state = next_green;

                default:
                    next_state = All_Red;
            endcase
        end
    end

    // ------------------------------------------------
    // 3. Fault-flashing timer
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            flash_timer <= '0;
            flash_on    <= 1'b1;
        end
        else if (fault_detect || state == Fault_Flash) begin
            if (flash_timer >= FLASH_TICKS - 1) begin
                flash_timer <= '0;
                flash_on    <= ~flash_on;
            end
            else begin
                flash_timer <= flash_timer + 1'b1;
            end
        end
        else begin
            flash_timer <= '0;
            flash_on    <= 1'b1;
        end
    end

    // ------------------------------------------------
    // 4. Decode FSM state into green/yellow requests
    // ------------------------------------------------
    always_comb begin
        req_N = 1'b0;
        req_E = 1'b0;
        req_S = 1'b0;
        req_W = 1'b0;

        yellow_N = 1'b0;
        yellow_E = 1'b0;
        yellow_S = 1'b0;
        yellow_W = 1'b0;

        case (state)
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

        // Overrides suppress normal green and yellow requests.
        if (emergency_vehicle || fault_detect ||
            state == Fault_Flash) begin
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
    // 5. Explicit mutual-exclusion interlock
    // ------------------------------------------------
    always_comb begin
        grant_N = req_N & ~req_E & ~req_S & ~req_W;
        grant_E = req_E & ~req_N & ~req_S & ~req_W;
        grant_S = req_S & ~req_N & ~req_E & ~req_W;
        grant_W = req_W & ~req_N & ~req_E & ~req_S;
    end

    // ------------------------------------------------
    // 6. Vehicle light outputs: {Red, Yellow, Green}
    // ------------------------------------------------
    always_comb begin
        light_N = {~(yellow_N | grant_N), yellow_N, grant_N};
        light_E = {~(yellow_E | grant_E), yellow_E, grant_E};
        light_S = {~(yellow_S | grant_S), yellow_S, grant_S};
        light_W = {~(yellow_W | grant_W), yellow_W, grant_W};

        // Fault mode: flashing red on all approaches.
        if (fault_detect || state == Fault_Flash) begin
            light_N = {flash_on, 1'b0, 1'b0};
            light_E = {flash_on, 1'b0, 1'b0};
            light_S = {flash_on, 1'b0, 1'b0};
            light_W = {flash_on, 1'b0, 1'b0};
        end
        // Emergency mode: steady red on all approaches.
        else if (emergency_vehicle) begin
            light_N = 3'b100;
            light_E = 3'b100;
            light_S = 3'b100;
            light_W = 3'b100;
        end
    end

    // ------------------------------------------------
    // 7. Pedestrian walk outputs
    // Bit 0 = North, 1 = East, 2 = South, 3 = West
    // ------------------------------------------------
    always_comb begin
        pedestrian_walk[0] = pedestrian_request[0] & grant_N;
        pedestrian_walk[1] = pedestrian_request[1] & grant_E;
        pedestrian_walk[2] = pedestrian_request[2] & grant_S;
        pedestrian_walk[3] = pedestrian_request[3] & grant_W;

        if (emergency_vehicle || fault_detect ||
            state == Fault_Flash)
            pedestrian_walk = 4'b0000;
    end

    // ------------------------------------------------
    // 8. State display output
    // ------------------------------------------------
    always_comb begin
        state_display = state;
    end

endmodule
