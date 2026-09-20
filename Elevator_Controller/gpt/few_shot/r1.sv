module elevator_fsm (
    input  logic       clk,
    input  logic       rst,

    // One request input for each floor: [3]=Floor 3, [0]=Floor 0
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

    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        MOVING_UP    = 3'b001,
        MOVING_DOWN  = 3'b010,
        DOOR_OPENING = 3'b011,
        DOOR_OPEN    = 3'b100,
        DOOR_CLOSING = 3'b101
    } state_t;

    state_t state, next_state;

    logic [3:0] requests;
    logic [3:0] next_requests;

    logic [3:0] timer;
    logic [3:0] next_timer;


    //========================================================
    // Sequential logic
    //========================================================

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


    //========================================================
    // Next-state and request logic
    //========================================================

    always_comb begin

        next_state   = state;
        next_requests = requests | floor_request;
        next_timer   = timer;

        case (state)

            //================================================
            // IDLE
            //================================================

            IDLE: begin

                if (requests[current_floor])
                    next_state = DOOR_OPENING;

                else if ((current_floor < 3) &&
                         (|requests[3:current_floor+1]))
                    next_state = MOVING_UP;

                else if ((current_floor > 0) &&
                         (|requests[current_floor-1:0]))
                    next_state = MOVING_DOWN;

            end


            //================================================
            // MOVING UP
            //================================================

            MOVING_UP: begin

                if (requests[current_floor])
                    next_state = DOOR_OPENING;

                else if (current_floor == 3)
                    next_state = DOOR_OPENING;

            end


            //================================================
            // MOVING DOWN
            //================================================

            MOVING_DOWN: begin

                if (requests[current_floor])
                    next_state = DOOR_OPENING;

                else if (current_floor == 0)
                    next_state = DOOR_OPENING;

            end


            //================================================
            // DOOR OPENING
            //================================================

            DOOR_OPENING: begin

                // Keep door opening for a few clock cycles
                if (timer == 4'd2)
                    next_state = DOOR_OPEN;

            end


            //================================================
            // DOOR OPEN
            //================================================

            DOOR_OPEN: begin

                // Current floor request is serviced
                next_requests[current_floor] = 1'b0;

                // Keep door open for a few cycles
                if (timer == 4'd5)
                    next_state = DOOR_CLOSING;

            end


            //================================================
            // DOOR CLOSING
            //================================================

            DOOR_CLOSING: begin

                // Reopen if obstacle is detected
                if (door_obstacle)
                    next_state = DOOR_OPENING;

                // Door closing completed
                else if (timer == 4'd2)
                    next_state = IDLE;

            end


            default: begin
                next_state = IDLE;
            end

        endcase

    end


    //========================================================
    // Output logic
    //========================================================

    always_comb begin

        // Default outputs
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

            default: begin
                motor_up   = 1'b0;
                motor_down = 1'b0;
                door_open  = 1'b0;
                door_close = 1'b0;
            end

        endcase

    end


    //========================================================
    // Current floor indicator
    //========================================================

    assign floor_indicator = current_floor;

endmodule
