`timescale 1ns/1ps

module elevator_fsm (
    input  logic       clk,
    input  logic       rst,

    // Floor requests
    // [3] = Floor 3
    // [2] = Floor 2
    // [1] = Floor 1
    // [0] = Floor 0
    input  logic [3:0] floor_request,

    // Current floor: 0 to 3
    input  logic [1:0] current_floor,

    // Door obstruction sensor
    input  logic       door_obstacle,

    // Outputs
    output logic       motor_up,
    output logic       motor_down,
    output logic       door_open,
    output logic       door_close,
    output logic [1:0] floor_indicator
);


    //====================================================
    // FSM STATES
    //====================================================

    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        MOVING_UP    = 3'b001,
        MOVING_DOWN  = 3'b010,
        DOOR_OPENING = 3'b011,
        DOOR_OPEN    = 3'b100,
        DOOR_CLOSING = 3'b101
    } state_t;

    state_t state;
    state_t next_state;


    //====================================================
    // REQUEST REGISTERS
    //====================================================

    logic [3:0] requests;
    logic [3:0] next_requests;


    //====================================================
    // TIMER
    //====================================================

    logic [3:0] timer;
    logic [3:0] next_timer;


    //====================================================
    // REQUEST FLAGS
    //====================================================

    logic request_here;
    logic request_above;
    logic request_below;

    integer i;


    //====================================================
    // SEQUENTIAL LOGIC
    //====================================================

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            state    <= IDLE;
            requests <= 4'b0000;
            timer    <= 4'd0;
        end

        else begin
            state    <= next_state;
            requests <= next_requests;

            if (state != next_state)
                timer <= 4'd0;
            else
                timer <= timer + 1'b1;
        end

    end


    //====================================================
    // REQUEST CLASSIFICATION
    //
    // This replaces the illegal dynamic part-selects.
    //====================================================

    always_comb begin

        request_here  = 1'b0;
        request_above = 1'b0;
        request_below = 1'b0;

        for (i = 0; i < 4; i = i + 1) begin

            if (requests[i] || floor_request[i]) begin

                if (i == current_floor) begin
                    request_here = 1'b1;
                end

                else if (i > current_floor) begin
                    request_above = 1'b1;
                end

                else begin
                    request_below = 1'b1;
                end

            end

        end

    end


    //====================================================
    // NEXT STATE LOGIC
    //====================================================

    always_comb begin

        // Default values
        next_state   = state;
        next_requests = requests | floor_request;
        next_timer   = timer;


        case (state)

            //================================================
            // IDLE
            //================================================

            IDLE: begin

                if (request_here) begin
                    next_state = DOOR_OPENING;
                end

                else if (request_above) begin
                    next_state = MOVING_UP;
                end

                else if (request_below) begin
                    next_state = MOVING_DOWN;
                end

                else begin
                    next_state = IDLE;
                end

            end


            //================================================
            // MOVING UP
            //================================================

            MOVING_UP: begin

                // When request is reached
                if (request_here) begin
                    next_state = DOOR_OPENING;
                end

                // Stop at top floor
                else if (current_floor == 2'd3) begin
                    next_state = IDLE;
                end

                else begin
                    next_state = MOVING_UP;
                end

            end


            //================================================
            // MOVING DOWN
            //================================================

            MOVING_DOWN: begin

                // When request is reached
                if (request_here) begin
                    next_state = DOOR_OPENING;
                end

                // Stop at ground floor
                else if (current_floor == 2'd0) begin
                    next_state = IDLE;
                end

                else begin
                    next_state = MOVING_DOWN;
                end

            end


            //================================================
            // DOOR OPENING
            //================================================

            DOOR_OPENING: begin

                // Door opening time = 3 clock cycles
                if (timer >= 4'd2)
                    next_state = DOOR_OPEN;

                else
                    next_state = DOOR_OPENING;

            end


            //================================================
            // DOOR OPEN
            //================================================

            DOOR_OPEN: begin

                // Service current-floor request
                next_requests[current_floor] = 1'b0;

                // Keep door open if obstacle exists
                if (door_obstacle) begin
                    next_state = DOOR_OPEN;
                end

                // Door open time = 6 clock cycles
                else if (timer >= 4'd5) begin
                    next_state = DOOR_CLOSING;
                end

                else begin
                    next_state = DOOR_OPEN;
                end

            end


            //================================================
            // DOOR CLOSING
            //================================================

            DOOR_CLOSING: begin

                // Reopen if obstacle detected
                if (door_obstacle) begin
                    next_state = DOOR_OPENING;
                end

                // Closing time = 3 clock cycles
                else if (timer >= 4'd2) begin
                    next_state = IDLE;
                end

                else begin
                    next_state = DOOR_CLOSING;
                end

            end


            //================================================
            // DEFAULT
            //================================================

            default: begin
                next_state = IDLE;
                next_requests = requests | floor_request;
            end

        endcase

    end


    //====================================================
    // OUTPUT LOGIC
    //====================================================

    always_comb begin

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
                motor_up   = 1'b0;
                motor_down = 1'b0;
                door_open  = 1'b0;
                door_close = 1'b0;
            end

            default: begin
                motor_up   = 1'b0;
                motor_down = 1'b0;
                door_open  = 1'b0;
                door_close = 1'b0;
            end

        endcase

    end


    //====================================================
    // FLOOR INDICATOR
    //====================================================

    assign floor_indicator = current_floor;


endmodule
