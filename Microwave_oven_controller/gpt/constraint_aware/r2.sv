module microwave_controller #(
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned TIMER_WIDTH  = 16
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

    //============================================================
    // State declaration
    //============================================================

    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        DOOR_OPEN = 3'b001,
        READY     = 3'b010,
        COOKING   = 3'b011,
        PAUSED    = 3'b100,
        DONE      = 3'b101
    } state_t;

    state_t state, next_state;

    //============================================================
    // 1-second clock tick counter
    //============================================================

    localparam int unsigned TICK_WIDTH =
        (CLK_FREQ_HZ <= 1) ? 1 : $clog2(CLK_FREQ_HZ);

    logic [TICK_WIDTH-1:0] tick_count;

    wire one_second_tick =
        (tick_count == CLK_FREQ_HZ - 1);

    //============================================================
    // Cooking timer
    //============================================================

    logic [TIMER_WIDTH-1:0] timer;

    //============================================================
    // State and timer registers
    //============================================================

    always_ff @(posedge clk) begin

        if (reset) begin
            state      <= IDLE;
            tick_count <= '0;
            timer      <= '0;
        end

        else begin

            // FSM state
            state <= next_state;

            // 1-second counter
            if (one_second_tick)
                tick_count <= '0;
            else
                tick_count <= tick_count + 1'b1;

            // Stop cancels the current timer
            if (stop) begin
                timer <= '0;
            end

            // Start a new cooking cycle
            else if ((state == READY) &&
                     start &&
                     door_closed &&
                     (timer_set != '0)) begin

                timer <= timer_set;
            end

            // Start a new cycle from DONE
            else if ((state == DONE) &&
                     start &&
                     door_closed &&
                     (timer_set != '0)) begin

                timer <= timer_set;
            end

            // Countdown during cooking
            else if ((state == COOKING) &&
                     one_second_tick &&
                     (timer != '0)) begin

                timer <= timer - 1'b1;
            end
        end
    end

    //============================================================
    // Next-state combinational logic
    //============================================================

    always_comb begin

        // Prevent inferred latch
        next_state = state;

        case (state)

            IDLE: begin
                if (!door_closed)
                    next_state = DOOR_OPEN;
                else
                    next_state = READY;
            end

            DOOR_OPEN: begin
                if (door_closed)
                    next_state = READY;
            end

            READY: begin
                if (!door_closed)
                    next_state = DOOR_OPEN;

                else if (stop)
                    next_state = IDLE;

                else if (start && (timer_set != '0))
                    next_state = COOKING;
            end

            COOKING: begin
                // Door safety has highest priority
                if (!door_closed)
                    next_state = PAUSED;

                else if (stop)
                    next_state = IDLE;

                else if (one_second_tick && (timer == 1))
                    next_state = DONE;
            end

            PAUSED: begin
                if (stop)
                    next_state = IDLE;

                else if (!door_closed)
                    next_state = DOOR_OPEN;

                else if (start && (timer != '0))
                    next_state = COOKING;
            end

            DONE: begin
                if (!door_closed)
                    next_state = DOOR_OPEN;

                else if (stop)
                    next_state = IDLE;

                else if (start && (timer_set != '0))
                    next_state = COOKING;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    //============================================================
    // Moore output logic
    //============================================================

    always_comb begin

        // Safe defaults prevent latches
        magnetron_on = 1'b0;
        light_on     = 1'b0;
        turntable_on = 1'b0;
        cooking      = 1'b0;
        done         = 1'b0;

        case (state)

            IDLE: begin
                // All outputs OFF
            end

            DOOR_OPEN: begin
                light_on = 1'b1;
            end

            READY: begin
                // All outputs OFF
            end

            COOKING: begin

                light_on = 1'b1;
                cooking  = 1'b1;

                // Safety interlock
                if (door_closed) begin
                    magnetron_on = 1'b1;
                    turntable_on = 1'b1;
                end
            end

            PAUSED: begin
                light_on = 1'b1;
            end

            DONE: begin
                light_on = 1'b1;
                done     = 1'b1;
            end

            default: begin
                // Safe OFF outputs
            end

        endcase
    end

endmodule
