`timescale 1ns/1ps

module traffic_controller_4way #(
    parameter longint unsigned CLK_FREQ_HZ      = 64'd100_000_000,
    parameter longint unsigned GREEN_TIME_SEC   = 64'd10,
    parameter longint unsigned YELLOW_TIME_SEC  = 64'd3,
    parameter longint unsigned ALL_RED_TIME_SEC = 64'd1,
    parameter longint unsigned FAULT_FLASH_HZ   = 64'd1
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       emergency_vehicle,
    input  logic       fault_detect,
    input  logic [3:0] pedestrian_request,

    // Light encoding: {Red, Yellow, Green}
    output logic [2:0] light_N,
    output logic [2:0] light_E,
    output logic [2:0] light_S,
    output logic [2:0] light_W,

    // Bit 0=N, bit 1=E, bit 2=S, bit 3=W
    output logic [3:0] pedestrian_walk
);

    // =========================================================
    // 1. FSM STATES
    // =========================================================
    (* fsm_encoding = "auto" *)
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

    // Current approach: 0=N, 1=E, 2=S, 3=W.
    logic [1:0] approach;

    // Set after a normally completed yellow phase.
    // Preserved during emergency/fault overrides.
    logic advance_pending;

    // =========================================================
    // 2. TWO-STAGE ASYNCHRONOUS INPUT SYNCHRONIZERS
    // =========================================================
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
        end else begin
            emergency_meta <= emergency_vehicle;
            emergency_sync <= emergency_meta;

            fault_meta <= fault_detect;
            fault_sync <= fault_meta;
        end
    end

    // =========================================================
    // 3. PARAMETER-DERIVED TIMER CONSTANTS
    //
    // All durations must be positive and their products must
    // fit in an unsigned 64-bit value.
    // =========================================================
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
        (MAX_PHASE_TICKS <= 64'd1)
            ? 1
            : $clog2(MAX_PHASE_TICKS);

    localparam logic [TIMER_WIDTH-1:0] GREEN_LAST =
        TIMER_WIDTH'(GREEN_TICKS - 64'd1);

    localparam logic [TIMER_WIDTH-1:0] YELLOW_LAST =
        TIMER_WIDTH'(YELLOW_TICKS - 64'd1);

    localparam logic [TIMER_WIDTH-1:0] ALL_RED_LAST =
        TIMER_WIDTH'(ALL_RED_TICKS - 64'd1);

    logic [TIMER_WIDTH-1:0] timer;
    logic [TIMER_WIDTH-1:0] phase_last;

    // Fault flash frequency is specified as full on/off cycles
    // per second. The output toggles every half-period.
    localparam longint unsigned SAFE_FLASH_HZ =
        (FAULT_FLASH_HZ == 64'd0) ? 64'd1 : FAULT_FLASH_HZ;

    localparam longint unsigned FLASH_HALF_TICKS =
        (CLK_FREQ_HZ / (64'd2 * SAFE_FLASH_HZ) < 64'd1)
            ? 64'd1
            : CLK_FREQ_HZ / (64'd2 * SAFE_FLASH_HZ);

    localparam integer FLASH_WIDTH =
        (FLASH_HALF_TICKS <= 64'd1)
            ? 1
            : $clog2(FLASH_HALF_TICKS);

    localparam logic [FLASH_WIDTH-1:0] FLASH_LAST =
        FLASH_WIDTH'(FLASH_HALF_TICKS - 64'd1);

    logic [FLASH_WIDTH-1:0] flash_timer;
    logic flash_on;

    // =========================================================
    // 4. SHARED PHASE TIMER TERMINAL-COUNT SELECTION
    // =========================================================
    always_comb begin
        phase_last = ALL_RED_LAST;

        case (state)
            N_Green, E_Green, S_Green, W_Green:
                phase_last = GREEN_LAST;

            N_Yellow, E_Yellow, S_Yellow, W_Yellow:
                phase_last = YELLOW_LAST;

            All_Red, Fault_Flash:
                phase_last = ALL_RED_LAST;

            default:
                phase_last = ALL_RED_LAST;
        endcase
    end

    // =========================================================
    // 5. NEXT-STATE LOGIC
    // Fault has priority over emergency.
    // Emergency holds the FSM in All_Red.
    // =========================================================
    always_comb begin
        next_state = state;

        if (fault_sync) begin
            next_state = Fault_Flash;
        end else if (state == Fault_Flash) begin
            next_state = All_Red;
        end else if (emergency_sync) begin
            next_state = All_Red;
        end else begin
            case (state)

                N_Green:
                    if (timer == GREEN_LAST)
                        next_state = N_Yellow;

                N_Yellow:
                    if (timer == YELLOW_LAST)
                        next_state = All_Red;

                E_Green:
                    if (timer == GREEN_LAST)
                        next_state = E_Yellow;

                E_Yellow:
                    if (timer == YELLOW_LAST)
                        next_state = All_Red;

                S_Green:
                    if (timer == GREEN_LAST)
                        next_state = S_Yellow;

                S_Yellow:
                    if (timer == YELLOW_LAST)
                        next_state = All_Red;

                W_Green:
                    if (timer == GREEN_LAST)
                        next_state = W_Yellow;

                W_Yellow:
                    if (timer == YELLOW_LAST)
                        next_state = All_Red;

                All_Red: begin
                    if (timer == ALL_RED_LAST) begin
                        if (advance_pending) begin
                            case (approach)
                                2'd0: next_state = E_Green;
                                2'd1: next_state = S_Green;
                                2'd2: next_state = W_Green;
                                2'd3: next_state = N_Green;
                                default: next_state = N_Green;
                            endcase
                        end else begin
                            case (approach)
                                2'd0: next_state = N_Green;
                                2'd1: next_state = E_Green;
                                2'd2: next_state = S_Green;
                                2'd3: next_state = W_Green;
                                default: next_state = N_Green;
                            endcase
                        end
                    end
                end

                default:
                    next_state = All_Red;

            endcase
        end
    end

    // =========================================================
    // 6. STATE REGISTER AND APPROACH TRACKING
    // =========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state          <= All_Red;
            approach       <= 2'd0;
            advance_pending <= 1'b0;
        end else begin
            state <= next_state;

            // A yellow phase completes normally only if neither
            // emergency nor fault overrides its terminal cycle.
            if (!fault_sync && !emergency_sync) begin
                case (state)
                    N_Yellow, E_Yellow, S_Yellow, W_Yellow: begin
                        if (timer == YELLOW_LAST)
                            advance_pending <= 1'b1;
                    end

                    default: begin
                        // No change.
                    end
                endcase

                // After the all-red clearance interval, advance
                // to the next approach if yellow completed normally.
                if (state == All_Red &&
                    timer == ALL_RED_LAST &&
                    advance_pending) begin

                    case (approach)
                        2'd0: approach <= 2'd1;
                        2'd1: approach <= 2'd2;
                        2'd2: approach <= 2'd3;
                        2'd3: approach <= 2'd0;
                        default: approach <= 2'd0;
                    endcase

                    advance_pending <= 1'b0;
                end
            end
        end
    end

    // =========================================================
    // 7. ONE SHARED PHASE TIMER
    // =========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            timer <= '0;
        end else if (state != next_state ||
                     fault_sync ||
                     emergency_sync) begin
            timer <= '0;
        end else if (timer == phase_last) begin
            timer <= '0;
        end else begin
            timer <= timer + {{(TIMER_WIDTH-1){1'b0}}, 1'b1};
        end
    end

    // =========================================================
    // 8. FAULT FLASH DIVIDER
    // =========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            flash_timer <= '0;
            flash_on    <= 1'b1;
        end else if (fault_sync || state == Fault_Flash) begin
            if (flash_timer == FLASH_LAST) begin
                flash_timer <= '0;
                flash_on    <= ~flash_on;
            end else begin
                flash_timer <=
                    flash_timer + {{(FLASH_WIDTH-1){1'b0}}, 1'b1};
            end
        end else begin
            flash_timer <= '0;
            flash_on    <= 1'b1;
        end
    end

    // =========================================================
    // 9. GREEN REQUEST DECODE AND MUTUAL-EXCLUSION INTERLOCK
    // =========================================================
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

            default: begin
                // All requests remain inactive.
            end
        endcase

        // Suppress normal indications during emergency and fault.
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

    // A green is granted only if it is the sole active request.
    always_comb begin
        grant_N = req_N & ~req_E & ~req_S & ~req_W;
        grant_E = req_E & ~req_N & ~req_S & ~req_W;
        grant_S = req_S & ~req_N & ~req_E & ~req_W;
        grant_W = req_W & ~req_N & ~req_E & ~req_S;
    end

    // =========================================================
    // 10. LATCH PEDESTRIAN REQUESTS UNTIL AN ALL-RED INTERVAL
    // =========================================================
    logic [3:0] pedestrian_pending;

    always_ff @(posedge clk) begin
        if (rst) begin
            pedestrian_pending <= 4'b0000;
        end else if (fault_sync || emergency_sync) begin
            // Preserve pending requests during overrides.
            pedestrian_pending <= pedestrian_pending |
                                  pedestrian_request;
        end else if (state == All_Red &&
                     next_state != All_Red) begin
            // The all-red interval has completed; served requests
            // are cleared before entering the next green phase.
            pedestrian_pending <= 4'b0000;
        end else begin
            pedestrian_pending <= pedestrian_pending |
                                  pedestrian_request;
        end
    end

    // =========================================================
    // 11. REGISTERED LIGHT AND PEDESTRIAN OUTPUTS
    // =========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            light_N         <= 3'b100;
            light_E         <= 3'b100;
            light_S         <= 3'b100;
            light_W         <= 3'b100;
            pedestrian_walk <= 4'b0000;
        end else if (fault_sync || next_state == Fault_Flash) begin
            // All approaches flash red; walk is disabled.
            light_N <= {flash_on, 1'b0, 1'b0};
            light_E <= {flash_on, 1'b0, 1'b0};
            light_S <= {flash_on, 1'b0, 1'b0};
            light_W <= {flash_on, 1'b0, 1'b0};

            pedestrian_walk <= 4'b0000;
        end else if (emergency_sync) begin
            light_N <= 3'b100;
            light_E <= 3'b100;
            light_S <= 3'b100;
            light_W <= 3'b100;

            pedestrian_walk <= 4'b0000;
        end else begin
            light_N <= {~(yellow_N | grant_N), yellow_N, grant_N};
            light_E <= {~(yellow_E | grant_E), yellow_E, grant_E};
            light_S <= {~(yellow_S | grant_S), yellow_S, grant_S};
            light_W <= {~(yellow_W | grant_W), yellow_W, grant_W};

            // Walk requests are granted during All_Red only.
            if (next_state == All_Red)
                pedestrian_walk <= pedestrian_pending |
                                   pedestrian_request;
            else
                pedestrian_walk <= 4'b0000;
        end
    end

endmodule
