module microwave_controller #(
    parameter int TIMER_WIDTH = 16
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  door_open,
    input  logic                  start,
    input  logic                  stop,

    // Cooking time loaded before starting
    input  logic [TIMER_WIDTH-1:0] time_set,

    output logic                  magnetron,
    output logic                  light,
    output logic                  turntable,
    output logic                  cooking,
    output logic                  done
);

    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        COOKING = 2'b01,
        PAUSED  = 2'b10,
        DONE    = 2'b11
    } state_t;

    state_t state, next_state;

    logic [TIMER_WIDTH-1:0] timer;

    //========================================================
    // State register and timer
    //========================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            timer <= '0;
        end
        else begin
            state <= next_state;

            // Load timer when starting from IDLE
            if (state == IDLE && start && !door_open)
                timer <= time_set;

            // Countdown during cooking
            else if (state == COOKING && !door_open && timer != 0)
                timer <= timer - 1'b1;

            // Restart after DONE
            else if (state == DONE && start && !door_open)
                timer <= time_set;
        end
    end

    //========================================================
    // Next-state logic
    //========================================================
    always_comb begin
        next_state = state;

        case (state)

            IDLE: begin
                if (start && !door_open && time_set != 0)
                    next_state = COOKING;
            end

            COOKING: begin
                // Door opening immediately pauses cooking
                if (door_open)
                    next_state = PAUSED;

                else if (stop)
                    next_state = IDLE;

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

    //========================================================
    // Output logic
    //========================================================
    always_comb begin

        // Safe defaults
        magnetron = 1'b0;
        light     = 1'b0;
        turntable = 1'b0;
        cooking   = 1'b0;
        done      = 1'b0;

        case (state)

            IDLE: begin
                // Light ON when door is open
                light = door_open;
            end

            COOKING: begin
                light   = 1'b1;
                cooking = 1'b1;

                // Safety interlock:
                // Magnetron can NEVER operate with door open
                if (!door_open) begin
                    magnetron = 1'b1;
                    turntable = 1'b1;
                end
            end

            PAUSED: begin
                light = 1'b1;
            end

            DONE: begin
                light = 1'b1;
                done  = 1'b1;
            end

            default: begin
                magnetron = 1'b0;
                light     = 1'b0;
                turntable = 1'b0;
                cooking   = 1'b0;
                done      = 1'b0;
            end

        endcase
    end

endmodule
