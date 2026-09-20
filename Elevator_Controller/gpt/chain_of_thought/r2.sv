module elevator_controller #(
    parameter int NUM_FLOORS = 4,
    parameter int OPEN_TIME  = 10,
    parameter int CLOSE_TIME = 10
)(
    input  logic clk,
    input  logic rst_n,

    // One request bit per floor
    input  logic [NUM_FLOORS-1:0] floor_request,

    // Current floor sensor
    input  logic [$clog2(NUM_FLOORS)-1:0] current_floor_sensor,

    // Travel limit switches
    input  logic up_limit,
    input  logic down_limit,

    // 1 = obstruction detected
    input  logic door_sensor,

    // Motor control
    output logic motor_up,
    output logic motor_down,

    // Door control
    output logic door_open,
    output logic door_close,

    // Floor display
    output logic [$clog2(NUM_FLOORS)-1:0] current_floor_display,

    // Direction indicators
    output logic direction_up,
    output logic direction_down
);

    localparam int FLOOR_W = $clog2(NUM_FLOORS);
    localparam int MAX_TIME =
        (OPEN_TIME > CLOSE_TIME) ? OPEN_TIME : CLOSE_TIME;

    localparam int TIMER_W = (MAX_TIME < 2) ? 1 : $clog2(MAX_TIME + 1);

    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        MOVING_UP    = 3'b001,
        MOVING_DOWN  = 3'b010,
        DOOR_OPENING = 3'b011,
        DOOR_OPEN    = 3'b100,
        DOOR_CLOSING = 3'b101
    } state_t;

    state_t state, next_state;

    logic [NUM_FLOORS-1:0] requests;
    logic [NUM_FLOORS-1:0] next_requests;

    logic [FLOOR_W-1:0] current_floor;
    logic [TIMER_W-1:0] timer;
    logic [TIMER_W-1:0] next_timer;

    logic request_here;
    logic request_above;
    logic request_below;

    integer i;

    // ============================================================
    // Determine pending requests relative to current floor
    // ============================================================

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

    // ============================================================
    // Sequential logic
    // ============================================================

    always_ff @(posedge clk) begin

        if (!rst_n) begin
            state         <= IDLE;
            requests      <= '0;
            current_floor <= '0;
            timer         <= '0;
        end

        else begin
            state         <= next_state;
            requests      <= next_requests;
            current_floor <= current_floor_sensor;
            timer         <= next_timer;
        end
    end

    // ============================================================
    // Next-state logic
    // ============================================================

    always_comb begin

        // Default values
        next_state   = state;
        next_requests = requests | floor_request;
        next_timer   = timer;

        case (state)

            // ----------------------------------------------------
            // IDLE
            // ----------------------------------------------------
            IDLE: begin

                next_timer = '0;

                if (request_here) begin
                    next_state = DOOR_OPENING;
                end

                else if (request_above) begin
                    next_state = MOVING_UP;
                end

                else if (request_below) begin
                    next_state = MOVING_DOWN;
                end
            end

            // ----------------------------------------------------
            // MOVING UP
            // ----------------------------------------------------
            MOVING_UP: begin

                next_timer = '0;

                if (request_here) begin
                    next_state = DOOR_OPENING;
                end

                else if (up_limit) begin
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

                else if (down_limit) begin
                    next_state = IDLE;
                end
            end

            // ----------------------------------------------------
            // DOOR OPENING
            // ----------------------------------------------------
            DOOR_OPENING: begin

                if (timer < OPEN_TIME) begin
                    next_timer = timer + 1'b1;
                end

                else begin
                    next_timer = '0;
                    next_state = DOOR_OPEN;
                end
            end

            // ----------------------------------------------------
            // DOOR OPEN
            // ----------------------------------------------------
            DOOR_OPEN: begin

                // Service the current floor
                next_requests[current_floor] = 1'b0;

                if (timer < OPEN_TIME) begin
                    next_timer = timer + 1'b1;
                end

                else begin
                    next_timer = '0;
                    next_state = DOOR_CLOSING;
                end
            end

            // ----------------------------------------------------
            // DOOR CLOSING
            // ----------------------------------------------------
            DOOR_CLOSING: begin

                // Reopen if obstruction is detected
                if (door_sensor) begin
                    next_timer = '0;
                    next_state = DOOR_OPENING;
                end

                else if (timer < CLOSE_TIME) begin
                    next_timer = timer + 1'b1;
                end

                else begin
                    next_timer = '0;
                    next_state = IDLE;
                end
            end

            // ----------------------------------------------------
            // Safety default
            // ----------------------------------------------------
            default: begin
                next_state = IDLE;
                next_timer = '0;
            end

        endcase
    end

    // ============================================================
    // Output logic
    // ============================================================

    always_comb begin

        // Default outputs
        motor_up       = 1'b0;
        motor_down     = 1'b0;

        door_open      = 1'b0;
        door_close     = 1'b0;

        direction_up   = 1'b0;
        direction_down = 1'b0;

        current_floor_display = current_floor;

        case (state)

            MOVING_UP: begin
                motor_up     = 1'b1;
                direction_up = 1'b1;
            end

            MOVING_DOWN: begin
                motor_down     = 1'b1;
                direction_down = 1'b1;
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

            default: begin
                // All outputs remain inactive
            end

        endcase
    end

endmodule
