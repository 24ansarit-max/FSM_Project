module elevator_controller #(
    parameter int NUM_FLOORS = 4
)(
    input  logic clk,
    input  logic rst,                         // synchronous reset

    input  logic [NUM_FLOORS-1:0] floor_request,

    input  logic [$clog2(NUM_FLOORS)-1:0] current_floor,

    input  logic door_obstacle,

    output logic motor_up,
    output logic motor_down,
    output logic door_open,
    output logic door_close,

    output logic [$clog2(NUM_FLOORS)-1:0] floor_indicator
);

    // =========================================================
    // FSM: Binary encoding
    // 6 states -> 3 flip-flops
    // =========================================================
    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        MOVING_UP    = 3'b001,
        MOVING_DOWN  = 3'b010,
        DOOR_OPENING = 3'b011,
        DOOR_OPEN    = 3'b100,
        DOOR_CLOSING = 3'b101
    } state_t;

    state_t state, next_state;

    // =========================================================
    // Pending floor requests
    // =========================================================
    logic [NUM_FLOORS-1:0] requests;
    logic [NUM_FLOORS-1:0] next_requests;

    logic request_here;
    logic request_above;
    logic request_below;

    integer i;

    // =========================================================
    // Request detection
    // =========================================================
    always_comb begin
        request_here  = 1'b0;
        request_above = 1'b0;
        request_below = 1'b0;

        for (i = 0; i < NUM_FLOORS; i = i + 1) begin
            if (requests[i]) begin
                if (i == current_floor)
                    request_here = 1'b1;
                else if (i > current_floor)
                    request_above = 1'b1;
                else
                    request_below = 1'b1;
            end
        end
    end

    // =========================================================
    // State and request registers
    // Synchronous reset
    // =========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            requests <= '0;
        end
        else begin
            state    <= next_state;
            requests <= next_requests;
        end
    end

    // =========================================================
    // Next-state logic
    // =========================================================
    always_comb begin

        // Default values avoid inferred latches
        next_state    = state;
        next_requests = requests | floor_request;

        case (state)

            IDLE: begin
                if (request_here)
                    next_state = DOOR_OPENING;
                else if (request_above)
                    next_state = MOVING_UP;
                else if (request_below)
                    next_state = MOVING_DOWN;
            end

            MOVING_UP: begin
                if (request_here)
                    next_state = DOOR_OPENING;
                else if (current_floor == NUM_FLOORS-1) begin
                    if (request_below)
                        next_state = MOVING_DOWN;
                    else
                        next_state = IDLE;
                end
            end

            MOVING_DOWN: begin
                if (request_here)
                    next_state = DOOR_OPENING;
                else if (current_floor == 0) begin
                    if (request_above)
                        next_state = MOVING_UP;
                    else
                        next_state = IDLE;
                end
            end

            DOOR_OPENING: begin
                // Simple one-cycle door-opening operation
                next_state = DOOR_OPEN;
            end

            DOOR_OPEN: begin
                // Service current floor request
                next_requests[current_floor] = 1'b0;
                next_state = DOOR_CLOSING;
            end

            DOOR_CLOSING: begin
                if (door_obstacle)
                    next_state = DOOR_OPENING;
                else
                    next_state = IDLE;
            end

            default: begin
                next_state    = IDLE;
                next_requests = '0;
            end

        endcase
    end

    // =========================================================
    // Moore output logic
    // =========================================================
    always_comb begin

        motor_up   = 1'b0;
        motor_down = 1'b0;
        door_open  = 1'b0;
        door_close = 1'b0;

        case (state)

            MOVING_UP:
                motor_up = 1'b1;

            MOVING_DOWN:
                motor_down = 1'b1;

            DOOR_OPENING:
                door_open = 1'b1;

            DOOR_OPEN:
                door_open = 1'b1;

            DOOR_CLOSING:
                door_close = 1'b1;

            default: begin
                motor_up   = 1'b0;
                motor_down = 1'b0;
                door_open  = 1'b0;
                door_close = 1'b0;
            end

        endcase
    end

    // =========================================================
    // Current floor indicator
    // =========================================================
    assign floor_indicator = current_floor;

endmodule
