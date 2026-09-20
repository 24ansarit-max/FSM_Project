module elevator_controller #(
    parameter int NUM_FLOORS = 4
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

    localparam int FLOOR_W = $clog2(NUM_FLOORS);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        UP   = 2'b01,
        DOWN = 2'b10,
        DOOR = 2'b11
    } state_t;

    state_t state, next_state;

    logic [NUM_FLOORS-1:0] requests;
    logic [NUM_FLOORS-1:0] next_requests;
    logic [FLOOR_W-1:0] next_floor;

    // ------------------------------------------------
    // Sequential logic
    // ------------------------------------------------
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

    // ------------------------------------------------
    // Next-state and request logic
    // ------------------------------------------------
    always_comb begin
        next_state   = state;
        next_floor   = current_floor;
        next_requests = requests | floor_request;

        case (state)

            IDLE: begin
                if (next_requests[current_floor]) begin
                    next_state = DOOR;
                end
                else if (current_floor < NUM_FLOORS-1 &&
                         |next_requests[NUM_FLOORS-1:current_floor+1]) begin
                    next_state = UP;
                end
                else if (current_floor > 0 &&
                         |next_requests[current_floor-1:0]) begin
                    next_state = DOWN;
                end
            end

            UP: begin
                if (current_floor < NUM_FLOORS-1) begin
                    next_floor = current_floor + 1'b1;

                    if (next_requests[current_floor + 1])
                        next_state = DOOR;
                end
                else begin
                    next_state = IDLE;
                end
            end

            DOWN: begin
                if (current_floor > 0) begin
                    next_floor = current_floor - 1'b1;

                    if (next_requests[current_floor - 1])
                        next_state = DOOR;
                end
                else begin
                    next_state = IDLE;
                end
            end

            DOOR: begin
                // Service current-floor request
                next_requests[current_floor] = 1'b0;

                // Keep door open while obstacle exists
                if (!door_obstacle)
                    next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
                next_floor = '0;
            end

        endcase
    end

    // ------------------------------------------------
    // Output logic
    // ------------------------------------------------
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

            default: begin
                motor_up   = 1'b0;
                motor_down = 1'b0;
                door_open  = 1'b0;
            end

        endcase
    end

endmodule
