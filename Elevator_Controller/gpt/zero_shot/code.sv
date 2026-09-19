`timescale 1ns/1ps

module elevator_controller #(
    parameter integer N = 4,
    parameter integer FLOOR_WIDTH = 2,
    parameter integer TRAVEL_TIME = 10,
    parameter integer DOOR_OPEN_TIME = 10,
    parameter integer DOOR_CLOSE_TIME = 5,
    parameter integer COUNTER_WIDTH = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // One request bit for each floor
    input  wire [N-1:0]             floor_request,

    // Current floor sensor
    input  wire [FLOOR_WIDTH-1:0]   current_floor,

    // High when an obstacle is detected at the door
    input  wire                     door_obstacle,

    // Motor control outputs
    output reg                      motor_up,
    output reg                      motor_down,

    // Door control outputs
    output reg                      door_open_signal,
    output reg                      door_close_signal,

    // Debug outputs
    output reg [2:0]                current_state,
    output reg [FLOOR_WIDTH-1:0]    floor_display
);

    // ---------------------------------------------------------
    // State encoding
    // ---------------------------------------------------------
    localparam [2:0]
        IDLE        = 3'b000,
        MOVING_UP   = 3'b001,
        MOVING_DOWN = 3'b010,
        DOOR_OPEN   = 3'b011,
        DOOR_CLOSED = 3'b100;


    // ---------------------------------------------------------
    // Internal registers
    // ---------------------------------------------------------

    reg [2:0] state;

    // Stores all pending floor requests
    reg [N-1:0] pending_requests;

    // Internal representation of elevator position
    reg [FLOOR_WIDTH-1:0] floor_reg;

    // Floor currently selected as the next destination
    reg [FLOOR_WIDTH-1:0] target_floor;

    // 1 = upward direction
    // 0 = downward direction
    reg direction_up;

    // Counter used for floor travel delay
    reg [COUNTER_WIDTH-1:0] travel_counter;

    // Counter used while door is open/closing
    reg [COUNTER_WIDTH-1:0] door_counter;

    integer i;
    integer distance;
    integer best_distance;
    integer found_request;
    integer found_above;
    integer found_below;


    // ---------------------------------------------------------
    // Main sequential FSM
    //
    // Handles:
    //   - State transitions
    //   - Request storage
    //   - Floor movement
    //   - Direction selection
    //   - SCAN scheduling
    //   - Door timing
    // ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state            <= IDLE;
            pending_requests <= {N{1'b0}};

            floor_reg        <= current_floor;
            target_floor     <= current_floor;

            direction_up     <= 1'b1;

            travel_counter   <= {COUNTER_WIDTH{1'b0}};
            door_counter     <= {COUNTER_WIDTH{1'b0}};

        end

        else begin

            // -------------------------------------------------
            // Store new floor requests
            // -------------------------------------------------
            pending_requests <= pending_requests | floor_request;


            case (state)

                // =================================================
                // IDLE
                // Find the nearest requested floor.
                // =================================================
                IDLE: begin

                    travel_counter <= {COUNTER_WIDTH{1'b0}};
                    door_counter   <= {COUNTER_WIDTH{1'b0}};

                    // Synchronize internal floor with sensor
                    floor_reg <= current_floor;

                    found_request = 0;
                    best_distance = N + 1;

                    // ------------------------------------------------
                    // Check if current floor itself is requested
                    // ------------------------------------------------
                    if (pending_requests[current_floor] ||
                        floor_request[current_floor]) begin

                        target_floor <= current_floor;

                        pending_requests[current_floor] <= 1'b0;

                        state <= DOOR_OPEN;

                        found_request = 1;
                    end

                    // ------------------------------------------------
                    // Otherwise find nearest request
                    // ------------------------------------------------
                    else begin

                        for (i = 0; i < N; i = i + 1) begin

                            if (pending_requests[i] ||
                                floor_request[i]) begin

                                if (i > current_floor)
                                    distance = i - current_floor;
                                else
                                    distance = current_floor - i;

                                if (distance < best_distance) begin

                                    best_distance = distance;
                                    target_floor <= i;

                                    found_request = 1;

                                    if (i > current_floor)
                                        direction_up <= 1'b1;
                                    else
                                        direction_up <= 1'b0;

                                end
                            end
                        end

                        // Start movement toward nearest request
                        if (found_request) begin

                            if (target_floor > current_floor)
                                state <= MOVING_UP;

                            else if (target_floor < current_floor)
                                state <= MOVING_DOWN;

                        end
                    end
                end


                // =================================================
                // MOVING UP
                //
                // Move one floor every TRAVEL_TIME clocks.
                // =================================================
                MOVING_UP: begin

                    direction_up <= 1'b1;

                    if (travel_counter < TRAVEL_TIME - 1) begin

                        travel_counter <= travel_counter + 1'b1;

                    end

                    else begin

                        travel_counter <= {COUNTER_WIDTH{1'b0}};

                        // Move elevator one floor upward
                        if (floor_reg < N - 1)
                            floor_reg <= floor_reg + 1'b1;


                        // ------------------------------------------------
                        // Check whether next floor has a request
                        // ------------------------------------------------
                        if ((floor_reg + 1'b1) == target_floor ||
                            pending_requests[floor_reg + 1'b1] ||
                            floor_request[floor_reg + 1'b1]) begin

                            pending_requests[floor_reg + 1'b1] <= 1'b0;

                            state <= DOOR_OPEN;
                        end
                    end
                end


                // =================================================
                // MOVING DOWN
                //
                // Move one floor every TRAVEL_TIME clocks.
                // =================================================
                MOVING_DOWN: begin

                    direction_up <= 1'b0;

                    if (travel_counter < TRAVEL_TIME - 1) begin

                        travel_counter <= travel_counter + 1'b1;

                    end

                    else begin

                        travel_counter <= {COUNTER_WIDTH{1'b0}};

                        // Move elevator one floor downward
                        if (floor_reg > 0)
                            floor_reg <= floor_reg - 1'b1;


                        // ------------------------------------------------
                        // Check whether next floor has a request
                        // ------------------------------------------------
                        if ((floor_reg - 1'b1) == target_floor ||
                            pending_requests[floor_reg - 1'b1] ||
                            floor_request[floor_reg - 1'b1]) begin

                            pending_requests[floor_reg - 1'b1] <= 1'b0;

                            state <= DOOR_OPEN;
                        end
                    end
                end


                // =================================================
                // DOOR OPEN
                //
                // Hold the door open for DOOR_OPEN_TIME clocks.
                // =================================================
                DOOR_OPEN: begin

                    travel_counter <= {COUNTER_WIDTH{1'b0}};

                    if (door_counter < DOOR_OPEN_TIME - 1) begin

                        door_counter <= door_counter + 1'b1;

                    end

                    else begin

                        door_counter <= {COUNTER_WIDTH{1'b0}};

                        state <= DOOR_CLOSED;
                    end
                end


                // =================================================
                // DOOR CLOSED / CLOSING
                //
                // If obstacle is detected, reopen door.
                //
                // Otherwise continue according to SCAN algorithm.
                // =================================================
                DOOR_CLOSED: begin

                    travel_counter <= {COUNTER_WIDTH{1'b0}};

                    // Reopen door immediately if obstacle exists
                    if (door_obstacle) begin

                        door_counter <= {COUNTER_WIDTH{1'b0}};

                        state <= DOOR_OPEN;
                    end

                    else if (door_counter < DOOR_CLOSE_TIME - 1) begin

                        door_counter <= door_counter + 1'b1;

                    end

                    else begin

                        door_counter <= {COUNTER_WIDTH{1'b0}};

                        found_above = 0;
                        found_below = 0;

                        // -----------------------------------------
                        // Search for requests above current floor
                        // -----------------------------------------
                        for (i = 0; i < N; i = i + 1) begin

                            if ((i > floor_reg) &&
                                (pending_requests[i] ||
                                 floor_request[i])) begin

                                found_above = 1;
                            end
                        end


                        // -----------------------------------------
                        // Search for requests below current floor
                        // -----------------------------------------
                        for (i = 0; i < N; i = i + 1) begin

                            if ((i < floor_reg) &&
                                (pending_requests[i] ||
                                 floor_request[i])) begin

                                found_below = 1;
                            end
                        end


                        // -----------------------------------------
                        // Current floor requested again
                        // -----------------------------------------
                        if (pending_requests[floor_reg] ||
                            floor_request[floor_reg]) begin

                            pending_requests[floor_reg] <= 1'b0;

                            state <= DOOR_OPEN;
                        end


                        // =========================================
                        // SCAN ALGORITHM
                        // =========================================
                        else if (direction_up) begin

                            // Continue upward if requests exist above
                            if (found_above) begin

                                best_distance = N + 1;

                                for (i = 0; i < N; i = i + 1) begin

                                    if ((i > floor_reg) &&
                                        (pending_requests[i] ||
                                         floor_request[i])) begin

                                        distance = i - floor_reg;

                                        if (distance < best_distance) begin

                                            best_distance = distance;
                                            target_floor <= i;
                                        end
                                    end
                                end

                                direction_up <= 1'b1;

                                state <= MOVING_UP;
                            end


                            // No request above: reverse direction
                            else if (found_below) begin

                                best_distance = N + 1;

                                for (i = 0; i < N; i = i + 1) begin

                                    if ((i < floor_reg) &&
                                        (pending_requests[i] ||
                                         floor_request[i])) begin

                                        distance = floor_reg - i;

                                        if (distance < best_distance) begin

                                            best_distance = distance;
                                            target_floor <= i;
                                        end
                                    end
                                end

                                direction_up <= 1'b0;

                                state <= MOVING_DOWN;
                            end


                            // No pending requests
                            else begin

                                state <= IDLE;
                            end
                        end


                        // =========================================
                        // Currently travelling downward
                        // =========================================
                        else begin

                            // Continue downward if requests exist below
                            if (found_below) begin

                                best_distance = N + 1;

                                for (i = 0; i < N; i = i + 1) begin

                                    if ((i < floor_reg) &&
                                        (pending_requests[i] ||
                                         floor_request[i])) begin

                                        distance = floor_reg - i;

                                        if (distance < best_distance) begin

                                            best_distance = distance;
                                            target_floor <= i;
                                        end
                                    end
                                end

                                direction_up <= 1'b0;

                                state <= MOVING_DOWN;
                            end


                            // No request below: reverse direction
                            else if (found_above) begin

                                best_distance = N + 1;

                                for (i = 0; i < N; i = i + 1) begin

                                    if ((i > floor_reg) &&
                                        (pending_requests[i] ||
                                         floor_request[i])) begin

                                        distance = i - floor_reg;

                                        if (distance < best_distance) begin

                                            best_distance = distance;
                                            target_floor <= i;
                                        end
                                    end
                                end

                                direction_up <= 1'b1;

                                state <= MOVING_UP;
                            end


                            // No pending requests
                            else begin

                                state <= IDLE;
                            end
                        end
                    end
                end


                // =================================================
                // Default safety state
                // =================================================
                default: begin

                    state <= IDLE;

                    travel_counter <= {COUNTER_WIDTH{1'b0}};
                    door_counter   <= {COUNTER_WIDTH{1'b0}};

                end

            endcase
        end
    end


    // ---------------------------------------------------------
    // Moore FSM Output Logic
    //
    // Outputs depend only on current state.
    // ---------------------------------------------------------
    always @(*) begin

        // Default values
        motor_up          = 1'b0;
        motor_down        = 1'b0;

        door_open_signal  = 1'b0;
        door_close_signal = 1'b0;

        current_state     = state;
        floor_display     = floor_reg;


        case (state)

            IDLE: begin
                motor_up          = 1'b0;
                motor_down        = 1'b0;
                door_open_signal  = 1'b0;
                door_close_signal = 1'b1;
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
                door_close_signal = 1'b1;
            end

        endcase
    end

endmodule
