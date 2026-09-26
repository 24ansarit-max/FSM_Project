module microwave_controller #(
    parameter int TIMER_WIDTH = 16
)(
    input  logic clk,
    input  logic reset,

    input  logic door_open,
    input  logic start,
    input  logic stop,

    input  logic [TIMER_WIDTH-1:0] time_set,

    output logic magnetron,
    output logic turntable,
    output logic light,
    output logic cooking,
    output logic done
);

    // FSM states
    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        COOKING = 2'b01,
        PAUSED  = 2'b10,
        DONE    = 2'b11
    } state_t;

    state_t state, next_state;

    logic [TIMER_WIDTH-1:0] timer;

    //====================================================
    // State Register and Countdown Timer
    //====================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            timer <= '0;
        end
        else begin
            state <= next_state;

            // Load timer when Start is pressed
            if (state == IDLE && start && !door_open) begin
                timer <= time_set;
            end

            // Countdown during cooking
            else if (state == COOKING &&
                     !door_open &&
                     timer != 0) begin
                timer <= timer - 1'b1;
            end
        end
    end

    //====================================================
    // Next State Logic
    //====================================================
    always_comb begin

        next_state = state;

        case (state)

            IDLE: begin
                if (start && !door_open && time_set != 0)
                    next_state = COOKING;
            end

            COOKING: begin
                if (stop)
                    next_state = IDLE;
                else if (door_open)
                    next_state = PAUSED;
                else if (timer == 1)
                    next_state = DONE;
            end

            PAUSED: begin
                if (stop)
                    next_state = IDLE;
                else if (start && !door_open)
                    next_state = COOKING;
            end

            DONE: begin
                if (stop)
                    next_state = IDLE;
                else if (start && !door_open && time_set != 0)
                    next_state = COOKING;
            end

            default:
                next_state = IDLE;

        endcase
    end

    //====================================================
    // Output Logic
    //====================================================
    always_comb begin

        // Default outputs
        magnetron = 1'b0;
        turntable = 1'b0;
        light     = 1'b0;
        cooking   = 1'b0;
        done      = 1'b0;

        case (state)

            IDLE: begin
                // Light is ON when door is open
                light = door_open;
            end

            COOKING: begin
                light   = 1'b1;
                cooking = 1'b1;

                // Safety interlock
                if (!door_open) begin
                    magnetron = 1'b1;
                    turntable = 1'b1;
                end
            end

            PAUSED: begin
                light     = 1'b1;
                magnetron = 1'b0;
                turntable = 1'b0;
            end

            DONE: begin
                light = 1'b1;
                done  = 1'b1;
            end

            default: begin
                magnetron = 1'b0;
                turntable = 1'b0;
                light     = 1'b0;
                cooking   = 1'b0;
                done      = 1'b0;
            end

        endcase
    end

endmodule
