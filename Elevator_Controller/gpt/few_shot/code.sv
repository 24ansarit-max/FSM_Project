`timescale 1ns/1ps

module elevator_controller #(
    parameter integer N = 4,
    parameter integer FLOOR_WIDTH = 2,
    parameter integer TRAVEL_TIME = 10,
    parameter integer DOOR_OPEN_TIME = 10,
    parameter integer DOOR_CLOSE_TIME = 5,
    parameter integer TIMER_WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // One request bit for each floor
    input  wire [N-1:0]           floor_request,

    // Current floor sensor
    input  wire [FLOOR_WIDTH-1:0] current_floor,

    // Door obstacle sensor
    input  wire                   door_obstacle,

    // Outputs
    output reg                    motor_up,
    output reg                    motor_down,
    output reg                    door_open_signal,
    output reg                    door_close_signal,

    // Debug outputs
    output reg [2:0]              current_state,
    output reg [FLOOR_WIDTH-1:0]  floor_display
);

    // ============================================================
    // State encoding
    // ============================================================
    localparam IDLE        = 3'b000;
    localparam MOVING_UP   = 3'b001;
    localparam MOVING_DOWN = 3'b010;
    localparam DOOR_OPEN   = 3'b011;
    localparam DOOR_CLOSED = 3'b100;

    reg [2:0] state;
    reg [2:0] next_state;

    // ============================================================
    // Request register
    // Each bit represents a pending request.
    // ============================================================
    reg [N-1:0] request_reg;

    // ============================================================
    // Floor and destination registers
    // ============================================================
    reg [FLOOR_WIDTH-1:0] floor_reg;
    reg [FLOOR_WIDTH-1:0] target_floor;

    // 1 = moving/servicing upward direction
    // 0 = moving/servicing downward direction
    reg direction_up;

    // ============================================================
    // Timers
    // ============================================================
    reg [TIMER_WIDTH-1:0] travel_timer;
    reg [TIMER_WIDTH-1:0] door_timer;

    // ============================================================
    // Temporary variables used by next-state logic
    // ============================================================
    integer i;
    integer distance;
    integer nearest_distance;

    reg found_request;
    reg found_above;
    reg found_below;

    // ============================================================
    // Sequential logic
    //
    // Updates:
    //   - FSM state
    //   - Request register
    //   - Current floor
    //   - Destination floor
    //   - Direction
    //   - Timers
    // ============================================================
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            state         <= IDLE;
            request_reg   <= 0;
            floor_reg     <= 0;
            target_floor  <= 0;
            direction_up  <= 1'b1;
            travel_timer  <= 0;
            door_timer    <= 0;
        end

        else begin

            // ----------------------------------------------------
            // Store incoming floor requests
            // ----------------------------------------------------
            request_reg <= request_reg | floor_request;

            // ----------------------------------------------------
            // Update FSM state
            // ----------------------------------------------------
            state <= next_state;

            // ----------------------------------------------------
            // Floor travel timer
            // ----------------------------------------------------
            if ((state == MOVING_UP) ||
                (state == MOVING_DOWN)) begin

                if (travel_timer < TRAVEL_TIME - 1)
                    travel_timer <= travel_timer + 1'b1;
                else
                    travel_timer <= 0;

            end
            else begin
                travel_timer <= 0;
            end

            // ----------------------------------------------------
            // Door timer
            // ----------------------------------------------------
            if ((state == DOOR_OPEN) ||
                (state == DOOR_CLOSED)) begin

                if (door_timer < DOOR_OPEN_TIME - 1)
                    door_timer <= door_timer + 1'b1;
                else
                    door_timer <= 0;

            end
            else begin
                door_timer <= 0;
            end

            // ----------------------------------------------------
            // Move one floor when travel timer expires
            // ----------------------------------------------------
            if (state == MOVING_UP) begin

                if (travel_timer == TRAVEL_TIME - 1) begin

                    if (floor_reg < N-1)
                        floor_reg <= floor_reg + 1'b1;

                end
            end

            else if (state == MOVING_DOWN) begin

                if (travel_timer == TRAVEL_TIME - 1) begin

                    if (floor_reg > 0)
                        floor_reg <= floor_reg - 1'b1;

                end
            end

            // ----------------------------------------------------
            // Clear request when destination is reached
            // ----------------------------------------------------
            if ((state == MOVING_UP) &&
                (travel_timer == TRAVEL_TIME - 1) &&
                ((floor_reg + 1'b1) == target_floor)) begin

                request_reg[target_floor] <= 1'b0;

            end

            else if ((state == MOVING_DOWN) &&
                     (travel_timer == TRAVEL_TIME - 1) &&
                     ((floor_reg - 1'b1) == target_floor)) begin

                request_reg[target_floor] <= 1'b0;

            end

            // ----------------------------------------------------
            // Clear request for current floor
            // ----------------------------------------------------
            if (state == IDLE &&
                request_reg[floor_reg]) begin

                request_reg[floor_reg] <= 1'b0;

            end

        end
    end

    // ============================================================
    // Next-state and scheduling logic
    //
    // Implements:
    //   1. Nearest-request selection when IDLE
    //   2. Continue in current direction
    //   3. Reverse when no requests remain in that direction
    //   4. Door timing
    //   5. Obstacle reopening
    // ============================================================
    always @(*) begin

        next_state = state;

        found_request  = 1'b0;
        found_above    = 1'b0;
        found_below    = 1'b0;

        nearest_distance = N + 1;

        // --------------------------------------------------------
        // Check for requests above and below current floor
        // --------------------------------------------------------
        for (i = 0; i < N; i = i + 1) begin

            if (request_reg[i] || floor_request[i]) begin

                if (i > floor_reg)
                    found_above = 1'b1;

                if (i < floor_reg)
                    found_below = 1'b1;

            end
        end

        // ========================================================
        // IDLE
        // Select nearest pending request
        // ========================================================
        case (state)

            IDLE: begin

                // Current floor requested
                if (request_reg[floor_reg] ||
                    floor_request[floor_reg]) begin

                    next_state = DOOR_OPEN;

                end

                else begin

                    found_request = 1'b0;
                    nearest_distance = N + 1;

                    // --------------------------------------------
                    // Search for nearest request
                    // --------------------------------------------
                    for (i = 0; i < N; i = i + 1) begin

                        if (request_reg[i] ||
                            floor_request[i]) begin

                            if (i > floor_reg)
                                distance = i - floor_reg;
                            else
                                distance = floor_reg - i;

                            if (distance < nearest_distance) begin

                                nearest_distance = distance;
                                found_request = 1'b1;

                                target_floor = i;

                            end
                        end
                    end

                    // --------------------------------------------
                    // Start moving toward nearest request
                    // --------------------------------------------
                    if (found_request) begin

                        if (target_floor > floor_reg) begin

                            direction_up = 1'b1;
                            next_state = MOVING_UP;

                        end

                        else if (target_floor < floor_reg) begin

                            direction_up = 1'b0;
                            next_state = MOVING_DOWN;

                        end
                    end
                end
            end


            // ====================================================
            // MOVING UP
            // ====================================================
            MOVING_UP: begin

                // Arrived at requested floor
                if ((travel_timer == TRAVEL_TIME - 1) &&
                    ((floor_reg + 1'b1) == target_floor)) begin

                    next_state = DOOR_OPEN;

                end

                // Continue upward while requests exist
                else if (found_above) begin

                    next_state = MOVING_UP;

                end

                // No requests above, reverse if requests below
                else if (found_below) begin

                    direction_up = 1'b0;
                    next_state = MOVING_DOWN;

                end

                else begin

                    next_state = IDLE;

                end
            end


            // ====================================================
            // MOVING DOWN
            // ====================================================
            MOVING_DOWN: begin

                // Arrived at requested floor
                if ((travel_timer == TRAVEL_TIME - 1) &&
                    ((floor_reg - 1'b1) == target_floor)) begin

                    next_state = DOOR_OPEN;

                end

                // Continue downward while requests exist
                else if (found_below) begin

                    next_state = MOVING_DOWN;

                end

                // No requests below, reverse if requests above
                else if (found_above) begin

                    direction_up = 1'b1;
                    next_state = MOVING_UP;

                end

                else begin

                    next_state = IDLE;

                end
            end


            // ====================================================
            // DOOR OPEN
            // ====================================================
            DOOR_OPEN: begin

                if (door_timer >= DOOR_OPEN_TIME - 1)
                    next_state = DOOR_CLOSED;
                else
                    next_state = DOOR_OPEN;

            end


            // ====================================================
            // DOOR CLOSED
            //
            // Obstacle causes immediate reopening.
            // ====================================================
            DOOR_CLOSED: begin

                if (door_obstacle) begin

                    next_state = DOOR_OPEN;

                end

                else if (door_timer >= DOOR_CLOSE_TIME - 1) begin

                    // Continue scanning for pending requests

                    if (found_above || found_below) begin

                        if (direction_up && found_above)
                            next_state = MOVING_UP;

                        else if (!direction_up && found_below)
                            next_state = MOVING_DOWN;

                        else if (found_above) begin

                            direction_up = 1'b1;
                            next_state = MOVING_UP;
                        end

                        else if (found_below) begin

                            direction_up = 1'b0;
                            next_state = MOVING_DOWN;
                        end

                    end

                    else begin

                        next_state = IDLE;

                    end

                end

                else begin

                    next_state = DOOR_CLOSED;

                end
            end


            // ====================================================
            // Default
            // ====================================================
            default: begin
                next_state = IDLE;
            end

        endcase
    end


    // ============================================================
    // Moore output logic
    //
    // Outputs depend only on the current FSM state.
    // ============================================================
    always @(*) begin

        // Default outputs
        motor_up         = 1'b0;
        motor_down       = 1'b0;
        door_open_signal = 1'b0;
        door_close_signal = 1'b0;

        current_state = state;
        floor_display = floor_reg;

        case (state)

            IDLE: begin
                motor_up          = 1'b0;
                motor_down        = 1'b0;
                door_open_signal  = 1'b0;
                door_close_signal = 1'b0;
            end

            MOVING_UP: begin
                motor_up          = 1'b1;
                motor_down        = 1'b0;
                door_open_signal  = 1'b0;
                door_close_signal = 1'b1;
            end

            MOVING_DOWN: begin
                motor_up          = 1'b0;
                motor_down        = 1'b1;
                door_open_signal  = 1'b0;
                door_close_signal = 1'b1;
            end

            DOOR_OPEN: begin
                motor_up          = 1'b0;
                motor_down        = 1'b0;
                door_open_signal  = 1'b1;
                door_close_signal = 1'b0;
            end

            DOOR_CLOSED: begin
                motor_up          = 1'b0;
                motor_down        = 1'b0;
                door_open_signal  = 1'b0;
                door_close_signal = 1'b1;
            end

            default: begin
                motor_up          = 1'b0;
                motor_down        = 1'b0;
                door_open_signal  = 1'b0;
                door_close_signal = 1'b0;
            end

        endcase
    end

endmodule
