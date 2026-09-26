module microwave_controller #(
    parameter int unsigned CLOCK_FREQ_HZ = 100_000_000,
    parameter int unsigned TIMER_WIDTH    = 16
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
    output logic                     done,

    // Remaining cooking time in seconds
    output logic [TIMER_WIDTH-1:0]   timer
);

    //========================================================
    // Parameters
    //========================================================

    localparam int unsigned TICK_WIDTH =
        (CLOCK_FREQ_HZ <= 1) ? 1 : $clog2(CLOCK_FREQ_HZ);

    //========================================================
    // State Declaration
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

    logic [TICK_WIDTH-1:0] tick_counter;
    logic                   one_second_tick;

    //========================================================
    // 1-Second Tick Generator
    //========================================================

    always_ff @(posedge clk) begin
        if (reset) begin
            tick_counter <= '0;
        end
        else if (tick_counter == CLOCK_FREQ_HZ - 1) begin
            tick_counter <= '0;
        end
        else begin
            tick_counter <= tick_counter + 1'b1;
        end
    end

    assign one_second_tick =
        (tick_counter == CLOCK_FREQ_HZ - 1);

    //========================================================
    // Next-State Logic
    //========================================================

    always_comb begin

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
                // Door has highest priority for safety
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

    //========================================================
    // State, Timer and Registered Outputs
    //========================================================

    always_ff @(posedge clk) begin

        if (reset) begin

            state          <= IDLE;
            timer          <= '0;

            magnetron_on   <= 1'b0;
            light_on       <= 1'b0;
            turntable_on   <= 1'b0;
            cooking        <= 1'b0;
            done           <= 1'b0;

        end
        else begin

            state <= next_state;

            // ----------------------------------------------
            // Timer control
            // ----------------------------------------------

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

            // ----------------------------------------------
            // Registered outputs
            // ----------------------------------------------

            magnetron_on <= 1'b0;
            light_on     <= 1'b0;
            turntable_on <= 1'b0;
            cooking      <= 1'b0;
            done         <= 1'b0;

            case (next_state)

                IDLE: begin
                    // All outputs remain OFF
                end

                DOOR_OPEN: begin
                    light_on <= 1'b1;
                end

                READY: begin
                    // Waiting for Start
                end

                COOKING: begin
                    cooking <= 1'b1;
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
                    // Safe OFF state
                end

            endcase
        end
    end

endmodule
