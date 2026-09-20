module elevator_fsm (
    input  logic       clk,
    input  logic       rst,

    // One request bit for each floor
    // floor_request[0] = Floor 0
    // floor_request[1] = Floor 1
    // floor_request[2] = Floor 2
    // floor_request[3] = Floor 3
    input  logic [3:0] floor_request,

    // Current floor from floor sensor
    input  logic [1:0] current_floor,

    // Door obstruction sensor
    input  logic       door_obstacle,

    // Outputs
    output logic       motor_up,
    output logic       motor_down,
    output logic       door_open,
    output logic       door_close,

    // Current floor indicator
    output logic [1:0] floor_indicator
);

    typedef enum logic [2:0] {
        IDLE,
        MOVING_UP,
        MOVING_DOWN,
        DOOR_OPENING,
        DOOR_OPEN,
        DOOR_CLOSING
    } state_t;

    state_t state, next_state;

    logic [3:0] requests;
    logic [3:0] next_requests;

    logic [3:0] timer;

    logic request_here;
    logic request_above;
    logic request_below;

    integer i;

    // ------------------------------------------------
    // Request detection
    // ------------------------------------------------
    always_comb begin
        request_here  = 1'b0;
        request_above = 1'b0;
        request_below = 1'b0;

        for (i = 0; i < 4; i = i + 1) begin
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

    // ------------------------------------------------
    // State and request registers
    // ------------------------------------------------
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

    // ------------------------------------------------
    // Next-state logic
    // ------------------------------------------------
    always_comb begin
        next_state    = state;
        next_requests = requests | floor_request;

        case (state)

            IDLE: begin
                if (request_here)
                    next_state = DOOR_OPENING;
                else if (request_above)
                    next_state = MOVING_UP;
                else if (request_below)
                    next_state = MOVING_DOWN;
            end

            MOVING_UP: begin
                if (request_here)
                    next_state = DOOR_OPENING;
                else if (current_floor == 2'd3) begin
                    if (request_below)
                        next_state = MOVING_DOWN;
                    else
                        next_state = IDLE;
                end
            end

            MOVING_DOWN: begin
                if (request_here)
                    next_state = DOOR_OPENING;
                else if (current_floor == 2'd0) begin
                    if (request_above)
                        next_state = MOVING_UP;
                    else
                        next_state = IDLE;
                end
            end

            DOOR_OPENING: begin
                if (timer == 4'd2)
                    next_state = DOOR_OPEN;
            end

            DOOR_OPEN: begin
                // Request at current floor has been served
                next_requests[current_floor] = 1'b0;

                if (timer == 4'd5)
                    next_state = DOOR_CLOSING;
            end

            DOOR_CLOSING: begin
                if (door_obstacle)
                    next_state = DOOR_OPENING;
                else if (timer == 4'd2)
                    next_state = IDLE;
            end

            default:
                next_state = IDLE;

        endcase
    end

    // ------------------------------------------------
    // Output logic
    // ------------------------------------------------
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

    // Current floor indicator
    assign floor_indicator = current_floor;

endmodule
