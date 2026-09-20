module elevator_controller #(
    parameter int NUM_FLOORS      = 4,
    parameter int DOOR_OPEN_TIME  = 5,
    parameter int DOOR_CLOSE_TIME = 2
)(
    input  logic                         clk,
    input  logic                         rst,            // synchronous active-high reset
    input  logic [NUM_FLOORS-1:0]        floor_request,
    input  logic [((NUM_FLOORS <= 2) ? 1 : $clog2(NUM_FLOORS))-1:0]
                                         current_floor,
    input  logic                         door_obstacle,

    output logic                         motor_up,
    output logic                         motor_down,
    output logic                         door_open,
    output logic                         door_close,

    output logic [((NUM_FLOORS <= 2) ? 1 : $clog2(NUM_FLOORS))-1:0]
                                         floor_indicator
);

    // ------------------------------------------------------------
    // Width calculations
    // ------------------------------------------------------------
    localparam int FLOOR_W =
        (NUM_FLOORS <= 2) ? 1 : $clog2(NUM_FLOORS);

    localparam int TIMER_MAX =
        (DOOR_OPEN_TIME > DOOR_CLOSE_TIME) ?
        DOOR_OPEN_TIME : DOOR_CLOSE_TIME;

    localparam int TIMER_W =
        (TIMER_MAX <= 1) ? 1 : $clog2(TIMER_MAX + 1);

    // ------------------------------------------------------------
    // Binary encoded FSM
    // 6 states -> 3 flip-flops
    // ------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        MOVING_UP    = 3'b001,
        MOVING_DOWN  = 3'b010,
        DOOR_OPENING = 3'b011,
        DOOR_OPEN    = 3'b100,
        DOOR_CLOSING = 3'b101
    } state_t;

    state_t state, next_state;

    // Pending floor requests
    logic [NUM_FLOORS-1:0] pending_requests;
    logic [NUM_FLOORS-1:0] next_pending_requests;

    // Door timing
    logic [TIMER_W-1:0] timer;
    logic [TIMER_W-1:0] next_timer;

    // Request information
    logic request_here;
    logic request_above;
    logic request_below;

    logic [NUM_FLOORS-1:0] active_requests;

    integer i;

    // ------------------------------------------------------------
    // Combine old requests with new button presses
    // ------------------------------------------------------------
    always_comb begin
        active_requests = pending_requests | floor_request;
    end

    // ------------------------------------------------------------
    // Determine request position relative to current floor
    // ------------------------------------------------------------
    always_comb begin
        request_here  = 1'b0;
        request_above = 1'b0;
        request_below = 1'b0;

        for (i = 0; i < NUM_FLOORS; i = i + 1) begin
            if (active_requests[i]) begin

                if (i == current_floor)
                    request_here = 1'b1;

                else if (i > current_floor)
                    request_above = 1'b1;

                else
                    request_below = 1'b1;
            end
        end
    end

    // ------------------------------------------------------------
    // Sequential logic
    // Synchronous reset
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin

        if (rst) begin
            state           <= IDLE;
            pending_requests <= '0;
            timer           <= '0;
        end

        else begin
            state            <= next_state;
            pending_requests <= next_pending_requests;
            timer            <= next_timer;
        end

    end

    // ------------------------------------------------------------
    // Next-state and register logic
    // ------------------------------------------------------------
    always_comb begin

        next_state            = state;
        next_pending_requests = active_requests;
        next_timer            = timer;

        case (state)

            // ----------------------------------------------------
            // IDLE
            // ----------------------------------------------------
            IDLE: begin

                next_timer = '0;

                if (request_here)
                    next_state = DOOR_OPENING;

                else if (request_above)
                    next_state = MOVING_UP;

                else if (request_below)
                    next_state = MOVING_DOWN;

            end

            // ----------------------------------------------------
            // MOVING UP
            // ----------------------------------------------------
            MOVING_UP: begin

                next_timer = '0;

                if (request_here) begin
                    next_state = DOOR_OPENING;
                end

                else if (current_floor == NUM_FLOORS-1) begin
                    // Top floor reached
                    if (request_below)
                        next_state = MOVING_DOWN;
                    else
                        next_state = IDLE;
                end

            end

            // ----------------------------------------------------
            // MOVING DOWN
            // ----------------------------------------------------
            MOVING_DOWN: begin

                next_timer = '0;

                if (request_here) begin
                    next_state = DOOR_OPENING;
                end

                else if (current_floor == 0) begin
                    // Ground floor reached
                    if (request_above)
                        next_state = MOVING_UP;
                    else
                        next_state = IDLE;
                end

            end

            // ----------------------------------------------------
            // DOOR OPENING
            // ----------------------------------------------------
            DOOR_OPENING: begin

                if (DOOR_OPEN_TIME <= 1) begin
                    next_timer = '0;
                    next_state = DOOR_OPEN;
                end

                else if (timer == DOOR_OPEN_TIME-1) begin
                    next_timer = '0;
                    next_state = DOOR_OPEN;
                end

                else begin
                    next_timer = timer + 1'b1;
                end

            end

            // ----------------------------------------------------
            // DOOR OPEN
            // ----------------------------------------------------
            DOOR_OPEN: begin

                // Current floor request has been serviced
                if (current_floor < NUM_FLOORS)
                    next_pending_requests[current_floor] = 1'b0;

                if (DOOR_CLOSE_TIME <= 1) begin
                    next_timer = '0;
                    next_state = DOOR_CLOSING;
                end

                else if (timer == DOOR_CLOSE_TIME-1) begin
                    next_timer = '0;
                    next_state = DOOR_CLOSING;
                end

                else begin
                    next_timer = timer + 1'b1;
                end

            end

            // ----------------------------------------------------
            // DOOR CLOSING
            // ----------------------------------------------------
            DOOR_CLOSING: begin

                if (door_obstacle) begin
                    next_timer = '0;
                    next_state = DOOR_OPENING;
                end

                else begin
                    next_timer = '0;
                    next_state = IDLE;
                end

            end

            // ----------------------------------------------------
            // Safety recovery
            // ----------------------------------------------------
            default: begin
                next_state            = IDLE;
                next_pending_requests = '0;
                next_timer            = '0;
            end

        endcase
    end

    // ------------------------------------------------------------
    // Moore output logic
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // Current floor display
    // ------------------------------------------------------------
    assign floor_indicator = current_floor;

endmodule
