module microwave_controller (
    input  logic clk,
    input  logic rst_n,
    input  logic door_open,
    input  logic start,
    input  logic stop,
    input  logic timer_done,

    output logic magnetron,
    output logic light,
    output logic turntable,
    output logic cooking
);

    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        COOKING = 2'b01,
        PAUSED  = 2'b10,
        DONE    = 2'b11
    } state_t;

    state_t state, next_state;

    // State register
    always_ff @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-state logic
    always_comb begin
        next_state = state;

        case (state)

            IDLE: begin
                if (start && !door_open)
                    next_state = COOKING;
            end

            COOKING: begin
                if (stop)
                    next_state = IDLE;
                else if (door_open)
                    next_state = PAUSED;
                else if (timer_done)
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
                else if (start && !door_open)
                    next_state = COOKING;
            end

            default:
                next_state = IDLE;

        endcase
    end

    // Output logic
    always_comb begin
        // Default outputs
        magnetron = 1'b0;
        light     = 1'b0;
        turntable = 1'b0;
        cooking   = 1'b0;

        case (state)

            IDLE: begin
                light = door_open;
            end

            COOKING: begin
                light     = 1'b1;
                cooking   = 1'b1;

                // Safety: never heat with door open
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
            end

            default: begin
                magnetron = 1'b0;
                light     = 1'b0;
                turntable = 1'b0;
                cooking   = 1'b0;
            end

        endcase
    end

endmodule
