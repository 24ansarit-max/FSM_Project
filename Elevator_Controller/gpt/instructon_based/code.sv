`timescale 1ns/1ps

module elevator_controller #(
    parameter integer NUM_FLOORS    = 4,
    parameter integer DOOR_OPEN_TIME = 10
)(
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire [NUM_FLOORS-1:0]             floor_request,
    input  wire                             door_obstacle,

    output reg                             motor_up,
    output reg                             motor_down,
    output reg                             door_open_out,
    output reg                             door_close_out,
    output reg [$clog2(NUM_FLOORS)-1:0]     current_floor,
    output reg [2:0]                        state_out
);

    // ============================================================
    // State encoding
    // ============================================================
    localparam [2:0]
        IDLE        = 3'b000,
        MOVING_UP   = 3'b001,
        MOVING_DOWN = 3'b010,
        DOOR_OPEN   = 3'b011,
        DOOR_CLOSED = 3'b100;

    // ============================================================
    // Internal parameters
    // ============================================================

    // Number of clock cycles required to travel one floor.
    localparam integer TRAVEL_TIME = 10;

    // Width of the floor counter.
    localparam integer FLOOR_WIDTH = $clog2(NUM_FLOORS);

    // Width required for the timing counters.
    localparam integer TIMER_WIDTH =
        (DOOR_OPEN_TIME < TRAVEL_TIME) ?
        $clog2(TRAVEL_TIME + 1) :
        $clog2(DOOR_OPEN_TIME + 1);

    // ============================================================
    // FSM registers
    // ============================================================
    reg [2:0] state;
    reg [2:0] next_state;

    // ============================================================
    // Request queue
    // One bit corresponds to one floor.
    // ============================================================
    reg [NUM_FLOORS-1:0] request_reg;
    reg [NUM_FLOORS-1:0] next_request_reg;

    // ============================================================
    // Direction
    // 1 = upward
    // 0 = downward
    // ============================================================
    reg direction_up;
    reg next_direction_up;

    // ============================================================
    // Target floor
    // ============================================================
    reg [FLOOR_WIDTH-1:0] target_floor;
    reg [FLOOR_WIDTH-1:0] next_target_floor;

    // ============================================================
    // Travel and door timers
    // ============================================================
    reg [TIMER_WIDTH-1:0] travel_counter;
    reg [TIMER_WIDTH-1:0] door_counter;

    // ============================================================
    // Temporary variables used by combinational logic
    // ============================================================
    integer i;
    integer distance;
    integer nearest_distance;

    reg request_above;
    reg request_below;
    reg request_anywhere;


    // ============================================================
    // SEQUENTIAL LOGIC
    //
    // Updates:
    //   - FSM state
    //   - Request queue
    //   - Current floor
    //   - Direction
    //   - Target floor
    //   - Timers
    // ============================================================
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            // ----------------------------------------------------
            // Reset: elevator starts at floor 0 in IDLE.
            // All pending requests are cleared.
            // ----------------------------------------------------
            state          <= IDLE;
            request_reg    <= {NUM_FLOORS{1'b0}};
            current_floor  <= {FLOOR_WIDTH{1'b0}};
            direction_up   <= 1'b1;
            target_floor   <= {FLOOR_WIDTH{1'b0}};
            travel_counter <= {TIMER_WIDTH{1'b0}};
            door_counter   <= {TIMER_WIDTH{1'b0}};

        end

        else begin

            // ----------------------------------------------------
            // Update FSM state from combinational next-state logic.
            // ----------------------------------------------------
            state <= next_state;

            // ----------------------------------------------------
            // Update request queue.
            // ----------------------------------------------------
            request_reg <= next_request_reg;

            // ----------------------------------------------------
            // Update current direction.
            // ----------------------------------------------------
            direction_up <= next_direction_up;

            // ----------------------------------------------------
            // Update selected target floor.
            // ----------------------------------------------------
            target_floor <= next_target_floor;

            // ----------------------------------------------------
            // MOVING_UP:
            // Count clock cycles required to travel one floor.
            // ----------------------------------------------------
            if (state == MOVING_UP) begin

                if (travel_counter < TRAVEL_TIME - 1) begin
                    travel_counter <= travel_counter + 1'b1;
                end

                else begin
                    travel_counter <= 0;

                    // Move exactly one floor upward.
                    if (current_floor < NUM_FLOORS - 1) begin
                        current_floor <= current_floor + 1'b1;
                    end
                end

            end

            // ----------------------------------------------------
            // MOVING_DOWN:
            // Count clock cycles required to travel one floor.
            // ----------------------------------------------------
            else if (state == MOVING_DOWN) begin

                if (travel_counter < TRAVEL_TIME - 1) begin
                    travel_counter <= travel_counter + 1'b1;
                end

                else begin
                    travel_counter <= 0;

                    // Move exactly one floor downward.
                    if (current_floor > 0) begin
                        current_floor <= current_floor - 1'b1;
                    end
                end

            end

            // ----------------------------------------------------
            // Elevator is not moving, so reset travel timer.
            // ----------------------------------------------------
            else begin
                travel_counter <= 0;
            end

            // ----------------------------------------------------
            // DOOR_OPEN:
            // Hold the door open for DOOR_OPEN_TIME cycles.
            // ----------------------------------------------------
            if (state == DOOR_OPEN) begin

                if (door_counter < DOOR_OPEN_TIME - 1) begin
                    door_counter <= door_counter + 1'b1;
                end

                else begin
                    door_counter <= 0;
                end

            end

            // ----------------------------------------------------
            // DOOR_CLOSED:
            // This represents the door-closing/closed interval.
            // The counter is reset here because closing is handled
            // as a one-cycle FSM state before selecting the next job.
            // ----------------------------------------------------
            else begin
                door_counter <= 0;
            end

        end
    end


    // ============================================================
    // COMBINATIONAL NEXT-STATE LOGIC
    //
    // Handles:
    //   - New requests
    //   - Nearest-request selection
    //   - SCAN direction control
    //   - Floor arrival
    //   - Door timing
    //   - Door obstacle detection
    // ============================================================
    always @(*) begin

        // --------------------------------------------------------
        // Default assignments.
        // --------------------------------------------------------
        next_state       = state;
        next_request_reg = request_reg | floor_request;
        next_direction_up = direction_up;
        next_target_floor = target_floor;

        request_above    = 1'b0;
        request_below    = 1'b0;
        request_anywhere = 1'b0;

        nearest_distance = NUM_FLOORS + 1;

        // --------------------------------------------------------
        // Find requests above, below, and anywhere.
        // Both stored requests and newly pressed buttons are used.
        // --------------------------------------------------------
        for (i = 0; i < NUM_FLOORS; i = i + 1) begin

            if (request_reg[i] || floor_request[i]) begin

                request_anywhere = 1'b1;

                if (i > current_floor) begin
                    request_above = 1'b1;
                end

                if (i < current_floor) begin
                    request_below = 1'b1;
                end

            end
        end


        // ========================================================
        // FSM STATE TRANSITIONS
        // ========================================================
        case (state)

            // ====================================================
            // IDLE
            //
            // No elevator movement. If a request exists at the
            // current floor, open the door. Otherwise find the
            // nearest pending request and select its direction.
            // ====================================================
            IDLE: begin

                // ------------------------------------------------
                // Request is already at the current floor.
                // ------------------------------------------------
                if (request_reg[current_floor] ||
                    floor_request[current_floor]) begin

                    // Clear the request because it is being serviced.
                    next_request_reg[current_floor] = 1'b0;

                    // Current floor becomes the target.
                    next_target_floor = current_floor;

                    // Open the door.
                    next_state = DOOR_OPEN;

                end

                // ------------------------------------------------
                // At least one request exists somewhere else.
                // ------------------------------------------------
                else if (request_anywhere) begin

                    // Search for the nearest pending floor.
                    for (i = 0; i < NUM_FLOORS; i = i + 1) begin

                        if (request_reg[i] || floor_request[i]) begin

                            // Calculate absolute distance.
                            if (i > current_floor)
                                distance = i - current_floor;
                            else
                                distance = current_floor - i;

                            // Keep the closest request.
                            if (distance < nearest_distance) begin

                                nearest_distance = distance;
                                next_target_floor = i;

                            end
                        end
                    end

                    // ------------------------------------------------
                    // Nearest request is above current floor.
                    // ------------------------------------------------
                    if (next_target_floor > current_floor) begin

                        next_direction_up = 1'b1;
                        next_state = MOVING_UP;

                    end

                    // ------------------------------------------------
                    // Nearest request is below current floor.
                    // ------------------------------------------------
                    else if (next_target_floor < current_floor) begin

                        next_direction_up = 1'b0;
                        next_state = MOVING_DOWN;

                    end

                end

                // ------------------------------------------------
                // No request exists.
                // Remain idle.
                // ------------------------------------------------
                else begin
                    next_state = IDLE;
                end

            end


            // ====================================================
            // MOVING_UP
            //
            // Move one floor every TRAVEL_TIME clock cycles.
            // Stop whenever the next floor contains a request.
            // ====================================================
            MOVING_UP: begin

                // ------------------------------------------------
                // One floor of travel has completed.
                // ------------------------------------------------
                if (travel_counter == TRAVEL_TIME - 1) begin

                    // ------------------------------------------------
                    // The next floor contains a request.
                    // Arrive and open the door.
                    // ------------------------------------------------
                    if ((current_floor + 1'b1 < NUM_FLOORS) &&
                        (request_reg[current_floor + 1'b1] ||
                         floor_request[current_floor + 1'b1])) begin

                        next_request_reg[current_floor + 1'b1] = 1'b0;

                        next_target_floor = current_floor + 1'b1;

                        next_state = DOOR_OPEN;

                    end

                    // ------------------------------------------------
                    // Continue upward when requests exist above.
                    // ------------------------------------------------
                    else if (request_above) begin

                        next_state = MOVING_UP;

                    end

                    // ------------------------------------------------
                    // No requests above, but requests exist below.
                    // Reverse direction.
                    // ------------------------------------------------
                    else if (request_below) begin

                        next_direction_up = 1'b0;

                        next_state = MOVING_DOWN;

                    end

                    // ------------------------------------------------
                    // No requests remain.
                    // Return to IDLE.
                    // ------------------------------------------------
                    else begin

                        next_state = IDLE;

                    end

                end

            end


            // ====================================================
            // MOVING_DOWN
            //
            // Move one floor every TRAVEL_TIME clock cycles.
            // Stop whenever the next floor contains a request.
            // ====================================================
            MOVING_DOWN: begin

                // ------------------------------------------------
                // One floor of travel has completed.
                // ------------------------------------------------
                if (travel_counter == TRAVEL_TIME - 1) begin

                    // ------------------------------------------------
                    // The next floor contains a request.
                    // Arrive and open the door.
                    // ------------------------------------------------
                    if ((current_floor > 0) &&
                        (request_reg[current_floor - 1'b1] ||
                         floor_request[current_floor - 1'b1])) begin

                        next_request_reg[current_floor - 1'b1] = 1'b0;

                        next_target_floor = current_floor - 1'b1;

                        next_state = DOOR_OPEN;

                    end

                    // ------------------------------------------------
                    // Continue downward when requests exist below.
                    // ------------------------------------------------
                    else if (request_below) begin

                        next_state = MOVING_DOWN;

                    end

                    // ------------------------------------------------
                    // No requests below, but requests exist above.
                    // Reverse direction.
                    // ------------------------------------------------
                    else if (request_above) begin

                        next_direction_up = 1'b1;

                        next_state = MOVING_UP;

                    end

                    // ------------------------------------------------
                    // No requests remain.
                    // Return to IDLE.
                    // ------------------------------------------------
                    else begin

                        next_state = IDLE;

                    end

                end

            end


            // ====================================================
            // DOOR_OPEN
            //
            // Hold the elevator door open for a fixed number
            // of clock cycles.
            // ====================================================
            DOOR_OPEN: begin

                // ------------------------------------------------
                // Door-open timer has expired.
                // Begin closing.
                // ------------------------------------------------
                if (door_counter >= DOOR_OPEN_TIME - 1) begin

                    next_state = DOOR_CLOSED;

                end

                // ------------------------------------------------
                // Door-open timer is still running.
                // ------------------------------------------------
                else begin

                    next_state = DOOR_OPEN;

                end

            end


            // ====================================================
            // DOOR_CLOSED
            //
            // Check the obstacle sensor first. If an obstacle is
            // detected, immediately reopen the door.
            //
            // Otherwise apply the SCAN scheduling algorithm.
            // ====================================================
            DOOR_CLOSED: begin

                // ------------------------------------------------
                // Obstacle detected while closing.
                // Reopen the door immediately.
                // ------------------------------------------------
                if (door_obstacle) begin

                    next_state = DOOR_OPEN;

                end

                // ------------------------------------------------
                // Continue in the current upward direction when
                // pending requests exist above the elevator.
                // ------------------------------------------------
                else if (direction_up && request_above) begin

                    next_state = MOVING_UP;

                end

                // ------------------------------------------------
                // Continue in the current downward direction when
                // pending requests exist below the elevator.
                // ------------------------------------------------
                else if (!direction_up && request_below) begin

                    next_state = MOVING_DOWN;

                end

                // ------------------------------------------------
                // No request remains in the current direction,
                // but a request exists above. Reverse upward.
                // ------------------------------------------------
                else if (request_above) begin

                    next_direction_up = 1'b1;

                    next_state = MOVING_UP;

                end

                // ------------------------------------------------
                // No request remains in the current direction,
                // but a request exists below. Reverse downward.
                // ------------------------------------------------
                else if (request_below) begin

                    next_direction_up = 1'b0;

                    next_state = MOVING_DOWN;

                end

                // ------------------------------------------------
                // No requests remain anywhere.
                // Return to IDLE.
                // ------------------------------------------------
                else begin

                    next_state = IDLE;

                end

            end


            // ====================================================
            // DEFAULT
            //
            // Recover from an invalid FSM state.
            // ====================================================
            default: begin

                next_state = IDLE;

            end

        endcase

    end


    // ============================================================
    // MOORE OUTPUT LOGIC
    //
    // Outputs depend only on the current FSM state.
    // ============================================================
    always @(*) begin

        // --------------------------------------------------------
        // Default output values.
        // --------------------------------------------------------
        motor_up       = 1'b0;
        motor_down     = 1'b0;
        door_open_out  = 1'b0;
        door_close_out = 1'b0;

        // Debug outputs.
        state_out      = state;

        // Current floor is directly displayed.
        // --------------------------------------------------------

        case (state)

            // ====================================================
            // IDLE
            // Elevator is stationary.
            // ====================================================
            IDLE: begin

                motor_up       = 1'b0;
                motor_down     = 1'b0;

                door_open_out  = 1'b0;
                door_close_out = 1'b0;

            end


            // ====================================================
            // MOVING_UP
            // Drive the elevator upward.
            // ====================================================
            MOVING_UP: begin

                motor_up       = 1'b1;
                motor_down     = 1'b0;

                door_open_out  = 1'b0;
                door_close_out = 1'b1;

            end


            // ====================================================
            // MOVING_DOWN
            // Drive the elevator downward.
            // ====================================================
            MOVING_DOWN: begin

                motor_up       = 1'b0;
                motor_down     = 1'b1;

                door_open_out  = 1'b0;
                door_close_out = 1'b1;

            end


            // ====================================================
            // DOOR_OPEN
            // Keep the door open.
            // ====================================================
            DOOR_OPEN: begin

                motor_up       = 1'b0;
                motor_down     = 1'b0;

                door_open_out  = 1'b1;
                door_close_out = 1'b0;

            end


            // ====================================================
            // DOOR_CLOSED
            // Keep the door closing/closed.
            // ====================================================
            DOOR_CLOSED: begin

                motor_up       = 1'b0;
                motor_down     = 1'b0;

                door_open_out  = 1'b0;
                door_close_out = 1'b1;

            end


            // ====================================================
            // DEFAULT
            // All outputs disabled for safety.
            // ====================================================
            default: begin

                motor_up       = 1'b0;
                motor_down     = 1'b0;

                door_open_out  = 1'b0;
                door_close_out = 1'b0;

            end

        endcase

    end

endmodule
