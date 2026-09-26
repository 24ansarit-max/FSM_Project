module microwave_controller #(
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned TIMER_WIDTH  = 16
)(
    input  logic                     clk,
    input  logic                     reset,

    input  logic                     door_closed,
    input  logic                     start,
    input  logic                     stop,

    // Cooking time in seconds
    input  logic [TIMER_WIDTH-1:0]   timer_set,

    output logic                     magnetron_on,
    output logic                     light_on,
    output logic                     turntable_on,
    output logic                     cooking,
    output logic                     done
);

    //========================================================
    // FSM states
    //========================================================

    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        DOOR_OPEN = 3'b001,
        READY     = 3'b010,
        COOKING   = 3'b011,
        PAUSED    = 3'b100,
        DONE      = 3'b101
    } state_t;

    state_t state, next_state;

    //========================================================
    // Timer
    //========================================================

    localparam int unsigned TICK_WIDTH =
        (CLK_FREQ_HZ <= 1) ? 1 : $clog2(CLK_FREQ_HZ);

    logic [TICK_WIDTH-1:0] tick_counter;
    logic [TIMER_WIDTH-1:0] timer;

    logic one_second_tick;

    assign one_second_tick =
        (tick_counter == CLK_FREQ_HZ - 1);

    //========================================================
    // State, timer and output registers
    //========================================================

    always_ff @(posedge clk) begin

        if (reset) begin

            state          <= IDLE;
            tick_counter   <= '0;
            timer          <= '0;

            magnetron_on   <= 1'b0;
            light_on       <= 1'b0;
            turntable_on   <= 1'b0;
            cooking        <= 1'b0;
            done           <= 1'b0;

        end
        else begin

            // State register
            state <= next_state;

            // -----------------------------------------------
            // 100 MHz -> 1 second tick
            // -----------------------------------------------

            if (one_second_tick)
                tick_counter <= '0;
            else
                tick_counter <= tick_counter + 1'b1;

            // -----------------------------------------------
            // Timer control
            // -----------------------------------------------

            if (stop) begin
                timer <= '0;
            end

            else if ((state == READY) &&
                     start &&
                     door_closed &&
                     (timer_set != '0)) begin

                timer <= timer_set;
            end

            else if ((state == DONE) &&
                     start &&
                     door_closed &&
                     (timer_set != '0)) begin

                timer <= timer_set;
            end

            else if ((state == COOKING) &&
                     one_second_tick &&
                     (timer != '0)) begin

                timer <= timer - 1'b1;
            end

            // -----------------------------------------------
            // Default output values
            // -----------------------------------------------

            magnetron_on <= 1'b0;
            light_on     <= 1'b0;
            turntable_on <= 1'b0;
            cooking      <= 1'b0;
            done         <= 1'b0;

            // -----------------------------------------------
            // Registered outputs based on NEXT state
            // -----------------------------------------------

            case (next_state)

                IDLE: begin
                    // Everything OFF
                end

                DOOR_OPEN: begin
                    light_on <= 1'b1;
                end

                READY: begin
                    // Everything OFF
                end

                COOKING: begin

                    light_on = 1'b1;
                    cooking  = 1'b1;

                    // Door safety interlock
                    if (door_closed) begin
                        magnetron_on = 1'b1;
                        turntable_on = 1'b1;
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
