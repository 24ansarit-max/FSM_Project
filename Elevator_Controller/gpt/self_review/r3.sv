module elevator_controller #(
    parameter int NUM_FLOORS = 4
)(
    input  logic clk,
    input  logic rst,                  // Synchronous active-high reset

    // One request bit for each floor
    input  logic [NUM_FLOORS-1:0] floor_request,

    // Current floor from external floor sensor
    input logic [((NUM_FLOORS <= 1) ? 1 : $clog2(NUM_FLOORS))-1:0]
               current_floor,

    // Door obstruction sensor
    input logic door_obstacle,

    // Elevator control outputs
    output logic motor_up,
    output logic motor_down,
    output logic door_open,
    output logic door_close,

    // Current floor display
    output logic [((NUM_FLOORS <= 1) ? 1 : $clog2(NUM_FLOORS))-1:0]
               floor_indicator
);

    // =========================================================
    // Floor width
    // =========================================================

    localparam int FLOOR_W =
        (NUM_FLOORS <= 1) ? 1 : $clog2(NUM_FLOORS);

    // =========================================================
    // FSM
    // Binary encoding:
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
    // Request registers
    // =========================================================

    logic [NUM_FLOORS-1:0] pending_requests;
    logic [NUM_FLOORS-1:0] next_requests;

    // Requests already stored + requests arriving this cycle
    logic [NUM_FLOORS-1:0] active_requests;

    // =========================================================
    // Request classification
    // =========================================================

    logic request_here;
    logic request_above;
    logic request_below;

    logic invalid_floor;

    integer i;

    // =========================================================
    // Combine pending and new requests
    // =========================================================

    always_comb begin
        active_requests = pending_requests | floor_request;
    end

    // =========================================================
    // Check whether current_floor is valid
    // =========================================================

    always_comb begin
        if (current_floor >= NUM_FLOORS)
            invalid_floor = 1'b1;
        else
            invalid_floor = 1'b0;
    end

    // =========================================================
    // Determine request position
    // =========================================================

    always_comb begin

        request_here  = 1'b0;
        request_above = 1'b0;
        request_below = 1'b0;

        if (!invalid_floor) begin

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
    end

    // =========================================================
    // Sequential logic
    // Synchronous reset
    // =========================================================

    always_ff @(posedge clk) begin

        if (rst) begin
            state            <= IDLE;
            pending_requests <= '0;
        end

        else begin
            state            <= next_state;
            pending_requests <= next_requests;
        end

    end

    // =========================================================
    // Next-state and request logic
    // =========================================================

    always_comb begin

        // Default values
        next_state   = state;
        next_requests = active_requests;

        // -----------------------------------------------------
        // Invalid floor sensor
        // -----------------------------------------------------

        if (invalid_floor) begin

            next_state = IDLE;

        end

        else begin

            case (state)

                // =============================================
                // IDLE
                // =============================================

                IDLE: begin

                    // Highest priority:
                    // request at current floor
                    if (request_here)
                        next_state = DOOR_OPENING;

                    // If requests exist above and below,
                    // UP direction gets priority.
                    else if (request_above)
                        next_state = MOVING_UP;

                    else if (request_below)
                        next_state = MOVING_DOWN;

                end

                // =============================================
                // MOVING UP
                // =============================================

                MOVING_UP: begin

                    // Stop when requested floor is reached
                    if (request_here) begin
                        next_state = DOOR_OPENING;
                    end

                    // Top floor reached
                    else if (current_floor == NUM_FLOORS-1) begin

                        if (request_below)
                            next_state = MOVING_DOWN;
                        else
                            next_state = IDLE;

                    end

                end

                // =============================================
                // MOVING DOWN
                // =============================================

                MOVING_DOWN: begin

                    // Stop when requested floor is reached
                    if (request_here) begin
                        next_state = DOOR_OPENING;
                    end

                    // Ground floor reached
                    else if (current_floor == 0) begin

                        if (request_above)
                            next_state = MOVING_UP;
                        else
                            next_state = IDLE;

                    end

                end

                // =============================================
                // DOOR OPENING
                // =============================================

                DOOR_OPENING: begin

                    // One clock cycle for opening operation
                    next_state = DOOR_OPEN;

                end

                // =============================================
                // DOOR OPEN
                // =============================================

                DOOR_OPEN: begin

                    // Current floor request is serviced
                    next_requests[current_floor] = 1'b0;

                    next_state = DOOR_CLOSING;

                end

                // =============================================
                // DOOR CLOSING
                // =============================================

                DOOR_CLOSING: begin

                    if (door_obstacle)
                        next_state = DOOR_OPENING;

                    else
                        next_state = IDLE;

                end

                // =============================================
                // Illegal-state recovery
                // =============================================

                default: begin

                    next_state = IDLE;
                    next_requests = active_requests;

                end

            endcase

        end

    end

    // =========================================================
    // Moore output logic
    // =========================================================

    always_comb begin

        // Safe default outputs
        motor_up   = 1'b0;
        motor_down = 1'b0;
        door_open  = 1'b0;
        door_close = 1'b0;

        case (state)

            MOVING_UP: begin
                motor_up = 1'b1;
            end

            MOVING_DOWN: begin
                motor_down = 1'b1;
            end

            DOOR_OPENING: begin
                door_open = 1'b1;
            end

            DOOR_OPEN: begin
                door_open = 1'b1;
            end

            DOOR_CLOSING: begin
                door_close = 1'b1;
            end

            IDLE: begin
                // All outputs remain LOW
            end

            default: begin
                motor_up   = 1'b0;
                motor_down = 1'b0;
                door_open  = 1'b0;
                door_close = 1'b0;
            end

        endcase

    end

    // =========================================================
    // Current-floor indicator
    // =========================================================

    assign floor_indicator = current_floor;

endmodule
