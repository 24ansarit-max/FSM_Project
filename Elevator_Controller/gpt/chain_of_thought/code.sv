`timescale 1ns/1ps

module elevator_controller #(
    parameter integer NUM_FLOORS       = 4,
    parameter integer TRAVEL_CYCLES    = 10,
    parameter integer DOOR_OPEN_CYCLES = 10,
    parameter integer DOOR_CLOSE_CYCLES = 5,

    parameter integer FLOOR_WIDTH =
        (NUM_FLOORS <= 2) ? 1 : $clog2(NUM_FLOORS),

    parameter integer TIMER_WIDTH =
        (TRAVEL_CYCLES > DOOR_OPEN_CYCLES &&
         TRAVEL_CYCLES > DOOR_CLOSE_CYCLES) ?
         ((TRAVEL_CYCLES <= 2) ? 1 : $clog2(TRAVEL_CYCLES)) :
        ((DOOR_OPEN_CYCLES > DOOR_CLOSE_CYCLES) ?
         ((DOOR_OPEN_CYCLES <= 2) ? 1 : $clog2(DOOR_OPEN_CYCLES)) :
         ((DOOR_CLOSE_CYCLES <= 2) ? 1 : $clog2(DOOR_CLOSE_CYCLES)))
)(
    input wire                       clk,
    input wire                       rst_n,

    // One request bit for each floor
    input wire [NUM_FLOORS-1:0]      floor_request,

    // External floor sensor
    input wire [FLOOR_WIDTH-1:0]     current_floor,

    // Door obstacle sensor
    input wire                       door_obstacle,

    // Elevator motor controls
    output reg                       motor_up,
    output reg                       motor_down,

    // Door controls
    output reg                       door_open_signal,
    output reg                       door_close_signal,

    // FSM state for debugging
    output reg [2:0]                 current_state,

    // Current floor display
    output reg [FLOOR_WIDTH-1:0]     floor_display
);

    // ============================================================
    // STEP 2: FSM STATE ENCODING
    // ============================================================

    localparam [2:0]
        IDLE        = 3'b000,
        MOVING_UP   = 3'b001,
        MOVING_DOWN = 3'b010,
        DOOR_OPEN   = 3'b011,
        DOOR_CLOSED = 3'b100;

    reg [2:0] state;
    reg [2:0] next_state;

    // ============================================================
    // STEP 3: REQUEST HANDLING
    // ============================================================

    reg [NUM_FLOORS-1:0] request_reg;
    reg [NUM_FLOORS-1:0] next_request_reg;

    // Target floor selected when a new movement starts
    reg [FLOOR_WIDTH-1:0] target_floor;
    reg [FLOOR_WIDTH-1:0] next_target_floor;

    // 1 = currently scanning upward
    // 0 = currently scanning downward
    reg direction_up;
    reg next_direction_up;

    // ============================================================
    // STEP 4: FLOOR MOVEMENT TIMING
    // ============================================================

    reg [FLOOR_WIDTH-1:0] floor_reg;
    reg [TIMER_WIDTH-1:0] travel_counter;

    // ============================================================
    // STEP 5: DOOR TIMING
    // ============================================================

    reg [TIMER_WIDTH-1:0] door_counter;

    // Temporary variables used by combinational logic
    integer i;
    integer distance;
    integer nearest_distance;

    reg request_above;
    reg request_below;
    reg request_anywhere;

    // ============================================================
    // STEP 6A:
    // SEQUENTIAL LOGIC
    //
    // Updates the FSM state, request register, floor position,
    // direction and timing counters.
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state          <= IDLE;

            request_reg    <= {NUM_FLOORS{1'b0}};

            floor_reg      <= {FLOOR_WIDTH{1'b0}};

            target_floor   <= {FLOOR_WIDTH{1'b0}};

            direction_up   <= 1'b1;

            travel_counter <= {TIMER_WIDTH{1'b0}};

            door_counter   <= {TIMER_WIDTH{1'b0}};

        end

        else begin

            // ----------------------------------------------------
            // Update FSM
            // ----------------------------------------------------
            state <= next_state;

            // ----------------------------------------------------
            // Update request register
            // ----------------------------------------------------
            request_reg <= next_request_reg;

            // ----------------------------------------------------
            // Update target and direction
            // ----------------------------------------------------
            target_floor <= next_target_floor;

            direction_up <= next_direction_up;

            // ----------------------------------------------------
            // STEP 4:
            // Travel timer
            // ----------------------------------------------------
            if (state == MOVING_UP ||
                state == MOVING_DOWN) begin

                if (travel_counter < TRAVEL_CYCLES - 1)
                    travel_counter <= travel_counter + 1'b1;
                else
                    travel_counter <= 0;

            end

            else begin

                travel_counter <= 0;

            end

            // ----------------------------------------------------
            // Update internal floor after one floor of travel
            // ----------------------------------------------------
            if (state == MOVING_UP) begin

                if (travel_counter == TRAVEL_CYCLES - 1) begin

                    if (floor_reg < NUM_FLOORS - 1)
                        floor_reg <= floor_reg + 1'b1;

                end

            end

            else if (state == MOVING_DOWN) begin

                if (travel_counter == TRAVEL_CYCLES - 1) begin

                    if (floor_reg > 0)
                        floor_reg <= floor_reg - 1'b1;

                end

            end

            // ----------------------------------------------------
            // Synchronize floor position with external sensor
            // whenever elevator is stationary.
            // ----------------------------------------------------
            else begin

                floor_reg <= current_floor;

            end

            // ----------------------------------------------------
            // STEP 5:
            // Door timer
            // ----------------------------------------------------
            if (state == DOOR_OPEN ||
                state == DOOR_CLOSED) begin

                if (door_counter < DOOR_OPEN_CYCLES - 1)
                    door_counter <= door_counter + 1'b1;
                else
                    door_counter <= 0;

            end

            else begin

                door_counter <= 0;

            end

        end
    end


    // ============================================================
    // STEP 6B:
    // COMBINATIONAL NEXT-STATE / REQUEST LOGIC
    //
    // Determines:
    //   - Next FSM state
    //   - Next target floor
    //   - Next direction
    //   - Requests to add/remove
    // ============================================================

    always @(*) begin

        // --------------------------------------------------------
        // Default values
        // --------------------------------------------------------

        next_state       = state;

        // New button presses are added to existing requests.
        next_request_reg = request_reg | floor_request;

        next_target_floor = target_floor;

        next_direction_up = direction_up;

        request_above    = 1'b0;
        request_below    = 1'b0;
        request_anywhere = 1'b0;

        nearest_distance = NUM_FLOORS + 1;

        // --------------------------------------------------------
        // Find pending requests above and below current floor.
        // Include new button presses immediately.
        // --------------------------------------------------------

        for (i = 0; i < NUM_FLOORS; i = i + 1) begin

            if (request_reg[i] || floor_request[i]) begin

                request_anywhere = 1'b1;

                if (i > floor_reg)
                    request_above = 1'b1;

                if (i < floor_reg)
                    request_below = 1'b1;

            end

        end


        // ========================================================
        // FSM TRANSITION LOGIC
        // ========================================================

        case (state)

            // ----------------------------------------------------
            // IDLE
            //
            // Select the nearest pending request.
            // ----------------------------------------------------

            IDLE: begin

                // Request at current floor
                if (request_reg[floor_reg] ||
                    floor_request[floor_reg]) begin

                    next_request_reg[floor_reg] = 1'b0;

                    next_target_floor = floor_reg;

                    next_state = DOOR_OPEN;

                end

                // Search for nearest request
                else if (request_anywhere) begin

                    for (i = 0; i < NUM_FLOORS; i = i + 1) begin

                        if (request_reg[i] ||
                            floor_request[i]) begin

                            if (i > floor_reg)
                                distance = i - floor_reg;
                            else
                                distance = floor_reg - i;

                            if (distance < nearest_distance) begin

                                nearest_distance = distance;

                                next_target_floor = i;

                            end

                        end

                    end

                    // Decide initial direction
                    if (next_target_floor > floor_reg) begin

                        next_direction_up = 1'b1;
                        next_state = MOVING_UP;

                    end

                    else if (next_target_floor < floor_reg) begin

                        next_direction_up = 1'b0;
                        next_state = MOVING_DOWN;

                    end

                end

                else begin

                    next_state = IDLE;

                end

            end


            // ----------------------------------------------------
            // MOVING UP
            //
            // Continue upward until the selected floor is reached.
            // Requests appearing at intermediate floors are also
            // serviced.
            // ----------------------------------------------------

            MOVING_UP: begin

                // One-floor arrival
                if (travel_counter == TRAVEL_CYCLES - 1) begin

                    // The next floor will be floor_reg + 1
                    if ((floor_reg + 1'b1) == target_floor ||
                        request_reg[floor_reg + 1'b1] ||
                        floor_request[floor_reg + 1'b1]) begin

                        next_request_reg[floor_reg + 1'b1] = 1'b0;

                        next_target_floor = floor_reg + 1'b1;

                        next_state = DOOR_OPEN;

                    end

                    // Reached top floor
                    else if (floor_reg == NUM_FLOORS - 1) begin

                        if (request_below) begin

                            next_direction_up = 1'b0;
                            next_state = MOVING_DOWN;

                        end

                        else begin

                            next_state = IDLE;

                        end

                    end

                    // Continue upward if requests remain above
                    else if (request_above) begin

                        next_state = MOVING_UP;

                    end

                    // No requests above, reverse
                    else if (request_below) begin

                        next_direction_up = 1'b0;

                        next_state = MOVING_DOWN;

                    end

                    else begin

                        next_state = IDLE;

                    end

                end

            end


            // ----------------------------------------------------
            // MOVING DOWN
            // ----------------------------------------------------

            MOVING_DOWN: begin

                // One-floor arrival
                if (travel_counter == TRAVEL_CYCLES - 1) begin

                    // The next floor will be floor_reg - 1
                    if ((floor_reg - 1'b1) == target_floor ||
                        request_reg[floor_reg - 1'b1] ||
                        floor_request[floor_reg - 1'b1]) begin

                        next_request_reg[floor_reg - 1'b1] = 1'b0;

                        next_target_floor = floor_reg - 1'b1;

                        next_state = DOOR_OPEN;

                    end

                    // Reached bottom floor
                    else if (floor_reg == 0) begin

                        if (request_above) begin

                            next_direction_up = 1'b1;
                            next_state = MOVING_UP;

                        end

                        else begin

                            next_state = IDLE;

                        end

                    end

                    // Continue downward
                    else if (request_below) begin

                        next_state = MOVING_DOWN;

                    end

                    // No requests below, reverse
                    else if (request_above) begin

                        next_direction_up = 1'b1;

                        next_state = MOVING_UP;

                    end

                    else begin

                        next_state = IDLE;

                    end

                end

            end


            // ----------------------------------------------------
            // DOOR_OPEN
            //
            // Keep doors open for the programmed time.
            // ----------------------------------------------------

            DOOR_OPEN: begin

                if (door_counter >= DOOR_OPEN_CYCLES - 1) begin

                    next_state = DOOR_CLOSED;

                end

                else begin

                    next_state = DOOR_OPEN;

                end

            end


            // ----------------------------------------------------
            // DOOR_CLOSED
            //
            // Door is closing/closed.
            // Obstacle immediately causes reopening.
            // ----------------------------------------------------

            DOOR_CLOSED: begin

                // Safety condition
                if (door_obstacle) begin

                    next_state = DOOR_OPEN;

                end

                else if (door_counter >= DOOR_CLOSE_CYCLES - 1) begin

                    // ------------------------------------------------
                    // Continue SCAN direction if possible
                    // ------------------------------------------------

                    if (direction_up && request_above) begin

                        next_state = MOVING_UP;

                    end

                    else if (!direction_up && request_below) begin

                        next_state = MOVING_DOWN;

                    end

                    // ------------------------------------------------
                    // No requests in current direction.
                    // Reverse if requests exist in the other direction.
                    // ------------------------------------------------

                    else if (request_above) begin

                        next_direction_up = 1'b1;

                        next_state = MOVING_UP;

                    end

                    else if (request_below) begin

                        next_direction_up = 1'b0;

                        next_state = MOVING_DOWN;

                    end

                    else if (request_reg[floor_reg] ||
                             floor_request[floor_reg]) begin

                        next_request_reg[floor_reg] = 1'b0;

                        next_state = DOOR_OPEN;

                    end

                    else begin

                        next_state = IDLE;

                    end

                end

                else begin

                    next_state = DOOR_CLOSED;

                end

            end


            // ----------------------------------------------------
            // Invalid state
            // ----------------------------------------------------

            default: begin

                next_state = IDLE;

            end

        endcase

    end


    // ============================================================
    // STEP 6C:
    // MOORE OUTPUT LOGIC
    //
    // Outputs depend only on the current FSM state.
    // ============================================================

    always @(*) begin

        // Default outputs
        motor_up          = 1'b0;
        motor_down        = 1'b0;

        door_open_signal  = 1'b0;
        door_close_signal = 1'b0;

        current_state     = state;
        floor_display     = floor_reg;

        case (state)

            // ----------------------------------------------------
            // IDLE
            // ----------------------------------------------------
            IDLE: begin

                motor_up          = 1'b0;
                motor_down        = 1'b0;

                door_open_signal  = 1'b0;
                door_close_signal = 1'b0;

            end


            // ----------------------------------------------------
            // MOVING UP
            // ----------------------------------------------------
            MOVING_UP: begin

                motor_up          = 1'b1;
                motor_down        = 1'b0;

                door_open_signal  = 1'b0;
                door_close_signal = 1'b1;

            end


            // ----------------------------------------------------
            // MOVING DOWN
            // ----------------------------------------------------
            MOVING_DOWN: begin

                motor_up          = 1'b0;
                motor_down        = 1'b1;

                door_open_signal  = 1'b0;
                door_close_signal = 1'b1;

            end


            // ----------------------------------------------------
            // DOOR OPEN
            // ----------------------------------------------------
            DOOR_OPEN: begin

                motor_up          = 1'b0;
                motor_down        = 1'b0;

                door_open_signal  = 1'b1;
                door_close_signal = 1'b0;

            end


            // ----------------------------------------------------
            // DOOR CLOSED
            // ----------------------------------------------------
            DOOR_CLOSED: begin

                motor_up          = 1'b0;
                motor_down        = 1'b0;

                door_open_signal  = 1'b0;
                door_close_signal = 1'b1;

            end


            // ----------------------------------------------------
            // Default
            // ----------------------------------------------------
            default: begin

                motor_up          = 1'b0;
                motor_down        = 1'b0;

                door_open_signal  = 1'b0;
                door_close_signal = 1'b0;

            end

        endcase

    end

endmodule
