module elevator_controller #(
    parameter int NUM_FLOORS = 4
)(
    input  logic clk,
    input  logic rst_n,                  // Active-low synchronous reset
    input  logic [NUM_FLOORS-1:0] floor_request,
    input  logic door_obstacle,

    output logic motor_up,
    output logic motor_down,
    output logic door_open,
    output logic [$clog2(NUM_FLOORS)-1:0] current_floor
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        UP   = 2'b01,
        DOWN = 2'b10,
        DOOR = 2'b11
    } state_t;

    state_t state;

    logic [NUM_FLOORS-1:0] requests;

    // ------------------------------------------------
    // Request register
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            requests <= '0;
        end
        else begin
            // Store new requests
            requests <= requests | floor_request;

            // Clear current floor request after servicing
            if (state == DOOR)
                requests[current_floor] <= 1'b0;
        end
    end

    // ------------------------------------------------
    // Elevator FSM
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state         <= IDLE;
            current_floor <= '0;
        end
        else begin

            case (state)

                IDLE: begin
                    if (requests[current_floor]) begin
                        state <= DOOR;
                    end
                    else if (current_floor < NUM_FLOORS-1 &&
                             requests[current_floor+1]) begin
                        state <= UP;
                    end
                    else if (current_floor > 0 &&
                             requests[current_floor-1]) begin
                        state <= DOWN;
                    end
                end

                UP: begin
                    if (current_floor < NUM_FLOORS-1) begin
                        current_floor <= current_floor + 1'b1;

                        if (requests[current_floor+1])
                            state <= DOOR;
                    end
                    else begin
                        state <= IDLE;
                    end
                end

                DOWN: begin
                    if (current_floor > 0) begin
                        current_floor <= current_floor - 1'b1;

                        if (requests[current_floor-1])
                            state <= DOOR;
                    end
                    else begin
                        state <= IDLE;
                    end
                end

                DOOR: begin
                    if (!door_obstacle)
                        state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
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
