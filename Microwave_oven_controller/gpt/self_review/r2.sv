module microwave_controller #(
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned TIMER_WIDTH = 16
)(
    input  logic                   clk,
    input  logic                   reset,

    input  logic                   door_closed,
    input  logic                   start,
    input  logic                   stop,

    // Cooking time in seconds
    input  logic [TIMER_WIDTH-1:0] timer_set,

    output logic                   magnetron_on,
    output logic                   light_on,
    output logic                   turntable_on,
    output logic                   cooking,
    output logic                   done
);

    //========================================================
    // 1-second tick counter sizing
    //========================================================

    localparam int unsigned TICK_WIDTH =
        (CLK_FREQ_HZ <= 1) ? 1 : $clog2(CLK_FREQ_HZ);

    // Width-matched terminal count
    localparam logic [TICK_WIDTH-1:0] TICK_MAX =
        CLK_FREQ_HZ - 1;

    //========================================================
    // FSM state declaration
    //========================================================

    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        DOOR_OPEN = 3'b001,
        READY     = 3'b010,
        COOKING   = 3'b011,
        PAUSED    = 3'b100,
        DONE      = 3'b101
    } state_t;

    state_t state;
    state_t next_state;

    //========================================================
    // Timer registers
    //========================================================

    logic [TICK_WIDTH-1:0]  tick_counter;
    logic [TIMER_WIDTH-1:0] timer;

    logic one_second_tick;

    assign one_second_tick = (tick_counter == TICK_MAX);

    //========================================================
    // State, timer and output registers
    //========================================================

    always_ff @(posedge clk) begin

        if (reset) begin

            state        <= IDLE;
            tick_counter <= '0;
            timer        <= '0;

            magnetron_on <= 1'b0;
            light_on     <= 1'b0;
            turntable_on <= 1'b0;
            cooking      <= 1'b0;
            done         <= 1'b0;

        end
        else begin

            //================================================
            // State register
            //================================================

            state <= next_state;

            //================================================
            // 1-second clock divider
            //================================================

            if (one_second_tick)
                tick_counter <= '0;
            else
                tick_counter <= tick_counter + 1'b1;

            //================================================
            // Cooking timer
            //================================================

            if (stop) begin

                // Cancel current operation
                timer <= '0;

            end
            else if ((state == READY) &&
                     start &&
                     door_closed &&
                     (timer_set != '0)) begin

                // Start new cooking cycle
                timer <= timer_set;

            end
            else if ((state == DONE) &&
                     start &&
                     door_closed &&
                     (timer_set != '0)) begin

                // Start a new cycle after completion
                timer <= timer_set;

            end
            else if ((state == COOKING) &&
                     one_second_tick &&
                     (timer > 1)) begin

                // Normal countdown
                timer <= timer - 1'b1;

            end
            else if ((state == COOKING) &&
                     one_second_tick &&
                     (timer == 1)) begin

                // Timer reaches zero
                timer <= '0;

            end

            //================================================
            // Safe default values for registered outputs
            //================================================

            magnetron_on <= 1'b0;
            light_on     <= 1'b0;
            turntable_on <= 1'b0;
            cooking      <= 1'b0;
            done         <= 1'b0;

            //================================================
            // Output control
            //================================================

            case (next_state)

                IDLE: begin
                    // All outputs OFF
                end

                DOOR_OPEN: begin
                    light_on <= 1'b1;
                end

                READY: begin
                    // All outputs OFF
                end

                COOKING: begin

                    cooking  <= 1'b1;
                    light_on <= 1'b1;

                    // Mandatory door interlock
                    if (door_closed) begin
                        magnetron_on <= 1'b1;
                        turntable_on <= 1'b1;
                    end

                end

                PAUSED: begin
                    light_on <= 1'b1;
                end

                DONE: begin
                    light_on <= 1'b1;
                    done     <= 1'b1;
                end

                default: begin
                    // Safe state
                    magnetron_on <= 1'b0;
                    light_on     <= 1'b0;
                    turntable_on <= 1'b0;
                    cooking      <= 1'b0;
                    done         <= 1'b0;
                end

            endcase

        end
    end

    //========================================================
    // Next-state combinational logic
    //========================================================

    always_comb begin

        // Default prevents inferred latch
        next_state = state;

        case (state)

            //================================================
            // IDLE
            //================================================

            IDLE: begin

                if (!door_closed)
                    next_state = DOOR_OPEN;
                else
                    next_state = READY;

            end

            //================================================
            // DOOR OPEN
            //================================================

            DOOR_OPEN: begin

                if (door_closed)
                    next_state = READY;

            end

            //================================================
            // READY
            //================================================

            READY: begin

                if (!door_closed)
                    next_state = DOOR_OPEN;

                else if (stop)
                    next_state = IDLE;

                else if (start && (timer_set != '0))
                    next_state = COOKING;

            end

            //================================================
            // COOKING
            //================================================

            COOKING: begin

                // Highest priority: door safety
                if (!door_closed)
                    next_state = PAUSED;

                else if (stop)
                    next_state = IDLE;

                else if (one_second_tick && (timer == 1))
                    next_state = DONE;

            end

            //================================================
            // PAUSED
            //================================================

            PAUSED: begin

                if (stop)
                    next_state = IDLE;

                else if (!door_closed)
                    next_state = DOOR_OPEN;

                // Resume only after Start
                else if (start && (timer != '0))
                    next_state = COOKING;

            end

            //================================================
            // DONE
            //================================================

            DONE: begin

                if (!door_closed)
                    next_state = DOOR_OPEN;

                else if (stop)
                    next_state = IDLE;

                else if (start && (timer_set != '0))
                    next_state = COOKING;

            end

            //================================================
            // Illegal state recovery
            //================================================

            default: begin
                next_state = IDLE;
            end

        endcase

    end

endmodule
