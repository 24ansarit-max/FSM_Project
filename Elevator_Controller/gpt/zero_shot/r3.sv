`timescale 1ns/1ps

module elevator_controller #(
    parameter integer NUM_FLOORS = 4
)(
    input  logic clk,
    input  logic rst_n,                         // Active-low synchronous reset
    input  logic [NUM_FLOORS-1:0] floor_request,
    input  logic door_obstacle,

    output logic motor_up,
    output logic motor_down,
    output logic door_open,
    output logic [$clog2(NUM_FLOORS)-1:0] current_floor
);

    localparam integer FLOOR_W = $clog2(NUM_FLOORS);

    //==================================================
    // FSM STATES
    //==================================================

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        UP   = 2'b01,
        DOWN = 2'b10,
        DOOR = 2'b11
    } state_t;

    state_t state;
    state_t next_state;

    //==================================================
    // REQUEST REGISTERS
    //==================================================

    logic [NUM_FLOORS-1:0] requests;
    logic [NUM_FLOORS-1:0] next_requests;

    logic [FLOOR_W-1:0] next_floor;

    logic request_here;
    logic request_above;
    logic request_below;

    integer i;


    //==================================================
    // SEQUENTIAL LOGIC
    //==================================================

    always_ff @(posedge clk) begin

        if (!rst_n) begin
            state         <= IDLE;
            current_floor <= '0;
            requests      <= '0;
        end

        else begin
            state         <= next_state;
            current_floor <= next_floor;
            requests      <= next_requests;
        end

    end


    //==================================================
    // REQUEST CLASSIFICATION
    // No dynamic part-selects are used here.
    //==================================================

    always_comb begin

        request_here  = 1'b0;
        request_above = 1'b0;
        request_below = 1'b0;

        for (i = 0; i < NUM_FLOORS; i = i + 1) begin

            if (requests[i] || floor_request[i]) begin

                if (i == current_floor)
                    request_here = 1'b1;

                else if (i > current_floor)
                    request_above = 1'b1;

                else
                    request_below = 1'b1;

            end

        end

    end


    //==================================================
    // NEXT STATE / NEXT FLOOR / REQUEST LOGIC
    //==================================================

    always_comb begin

        // Default values
        next_state   = state;
        next_floor   = current_floor;
        next_requests = requests | floor_request;


        case (state)

            //================================================
            // IDLE
            //================================================

            IDLE: begin

                // Request at current floor
                if (request_here) begin
                    next_state = DOOR;
                end

                // Request above current floor
                else if (request_above) begin
                    next_state = UP;
                end

                // Request below current floor
                else if (request_below) begin
                    next_state = DOWN;
                end

                else begin
                    next_state = IDLE;
                end

            end


            //================================================
            // MOVE UP
            //================================================

            UP: begin

                if (current_floor < NUM_FLOORS-1) begin

                    // Move one floor upward
                    next_floor = current_floor + 1'b1;

                    // If request exists at new floor,
                    // open the door
                    if (request_at_floor(current_floor + 1'b1))
                        next_state = DOOR;

                    else
                        next_state = UP;

                end

                else begin
                    // Top floor reached
                    next_state = IDLE;
                end

            end


            //================================================
            // MOVE DOWN
            //================================================

            DOWN: begin

                if (current_floor > 0) begin

                    // Move one floor downward
                    next_floor = current_floor - 1'b1;

                    // If request exists at new floor,
                    // open the door
                    if (request_at_floor(current_floor - 1'b1))
                        next_state = DOOR;

                    else
                        next_state = DOWN;

                end

                else begin
                    // Ground floor reached
                    next_state = IDLE;
                end

            end


            //================================================
            // DOOR
            //================================================

            DOOR: begin

                // Service current-floor request
                next_requests[current_floor] = 1'b0;

                // Keep door open when obstacle exists
                if (door_obstacle)
                    next_state = DOOR;

                else
                    next_state = IDLE;

            end


            //================================================
            // DEFAULT
            //================================================

            default: begin

                next_state = IDLE;
                next_floor = '0;
                next_requests = requests | floor_request;

            end

        endcase

    end


    //==================================================
    // FUNCTION
    // Checks whether a request exists at a floor.
    // This replaces illegal dynamic part-selects.
    //==================================================

    function automatic logic request_at_floor(
        input logic [FLOOR_W-1:0] floor
    );

        begin

            if (floor < NUM_FLOORS)
                request_at_floor =
                    requests[floor] | floor_request[floor];

            else
                request_at_floor = 1'b0;

        end

    endfunction


    //==================================================
    // OUTPUT LOGIC
    //==================================================

    always_comb begin

        motor_up   = 1'b0;
        motor_down = 1'b0;
        door_open  = 1'b0;

        case (state)

            UP: begin
                motor_up = 1'b1;
            end

            DOWN: begin
                motor_down = 1'b1;
            end

            DOOR: begin
                door_open = 1'b1;
            end

            IDLE: begin
                motor_up   = 1'b0;
                motor_down = 1'b0;
                door_open  = 1'b0;
            end

            default: begin
                motor_up   = 1'b0;
                motor_down = 1'b0;
                door_open  = 1'b0;
            end

        endcase

    end

endmodule
