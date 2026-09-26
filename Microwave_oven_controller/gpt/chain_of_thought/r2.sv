module microwave_controller (
    input  logic clk,
    input  logic reset,

    input  logic door_closed,
    input  logic start,
    input  logic stop,
    input  logic timer_set,
    input  logic timeout,

    output logic magnetron_on,
    output logic light_on,
    output logic turntable_on,
    output logic buzzer,
    output logic cooking
);

    //====================================================
    // State Declaration
    //====================================================

    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        DOOR_OPEN = 3'b001,
        READY     = 3'b010,
        COOKING   = 3'b011,
        PAUSED    = 3'b100,
        DONE      = 3'b101
    } state_t;

    state_t state, next_state;


    //====================================================
    // State Register
    //====================================================

    always_ff @(posedge clk) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end


    //====================================================
    // Next-State Logic
    //====================================================

    always_comb begin

        // Default: remain in current state
        next_state = state;

        case (state)

            // --------------------------------------------
            // IDLE
            // --------------------------------------------
            IDLE: begin
                if (!door_closed)
                    next_state = DOOR_OPEN;
                else
                    next_state = READY;
            end


            // --------------------------------------------
            // DOOR OPEN
            // --------------------------------------------
            DOOR_OPEN: begin
                if (door_closed)
                    next_state = READY;
            end


            // --------------------------------------------
            // READY
            // --------------------------------------------
            READY: begin
                if (!door_closed)
                    next_state = DOOR_OPEN;

                else if (stop)
                    next_state = IDLE;

                else if (start && timer_set)
                    next_state = COOKING;
            end


            // --------------------------------------------
            // COOKING
            // --------------------------------------------
            COOKING: begin

                // Door has highest priority for safety
                if (!door_closed)
                    next_state = PAUSED;

                else if (stop)
                    next_state = IDLE;

                else if (timeout)
                    next_state = DONE;
            end


            // --------------------------------------------
            // PAUSED
            // --------------------------------------------
            PAUSED: begin

                if (stop)
                    next_state = IDLE;

                else if (!door_closed)
                    next_state = DOOR_OPEN;

                else if (start && timer_set)
                    next_state = COOKING;
            end


            // --------------------------------------------
            // DONE
            // --------------------------------------------
            DONE: begin

                if (!door_closed)
                    next_state = DOOR_OPEN;

                else if (stop)
                    next_state = IDLE;

                else if (start && timer_set)
                    next_state = COOKING;
            end


            // --------------------------------------------
            // Illegal State
            // --------------------------------------------
            default: begin
                next_state = IDLE;
            end

        endcase
    end


    //====================================================
    // Output Logic
    //====================================================

    always_comb begin

        // Safe defaults
        magnetron_on = 1'b0;
        light_on     = 1'b0;
        turntable_on = 1'b0;
        buzzer       = 1'b0;
        cooking      = 1'b0;

        case (state)

            // --------------------------------------------
            // IDLE
            // --------------------------------------------
            IDLE: begin
                light_on = 1'b0;
            end


            // --------------------------------------------
            // DOOR OPEN
            // --------------------------------------------
            DOOR_OPEN: begin
                light_on     = 1'b1;
                magnetron_on = 1'b0;
                turntable_on = 1'b0;
            end


            // --------------------------------------------
            // READY
            // --------------------------------------------
            READY: begin
                light_on = 1'b0;
            end


            // --------------------------------------------
            // COOKING
            // --------------------------------------------
            COOKING: begin

                light_on = 1'b1;
                cooking  = 1'b1;

                // Safety interlock
                if (door_closed) begin
                    magnetron_on = 1'b1;
                    turntable_on = 1'b1;
                end
            end


            // --------------------------------------------
            // PAUSED
            // --------------------------------------------
            PAUSED: begin
                light_on     = 1'b1;
                magnetron_on = 1'b0;
                turntable_on = 1'b0;
                cooking      = 1'b0;
            end


            // --------------------------------------------
            // DONE
            // --------------------------------------------
            DONE: begin
                light_on     = 1'b1;
                magnetron_on = 1'b0;
                turntable_on = 1'b0;
                buzzer       = 1'b1;
                cooking      = 1'b0;
            end


            // --------------------------------------------
            // Default
            // --------------------------------------------
            default: begin
                magnetron_on = 1'b0;
                light_on     = 1'b0;
                turntable_on = 1'b0;
                buzzer       = 1'b0;
                cooking      = 1'b0;
            end

        endcase
    end

endmodule
