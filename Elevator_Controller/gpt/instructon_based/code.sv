module elevator_controller #(
    parameter NUM_FLOORS = 4
)(
    input clk,
    input rst_n,

    input  [NUM_FLOORS-1:0] floor_request,
    input                   door_obstacle,

    output reg motor_up,
    output reg motor_down,
    output reg door_open_out,
    output reg door_close_out,

    output reg [$clog2(NUM_FLOORS)-1:0] current_floor,
    output reg [2:0] state_out
);

    // Fixed timing values.
    localparam TRAVEL_CYCLES  = 10;
    localparam DOOR_OPEN_TIME = 5;

    // FSM state encodings.
    localparam [2:0] IDLE         = 3'b000;
    localparam [2:0] MOVING_UP   = 3'b001;
    localparam [2:0] MOVING_DOWN = 3'b010;
    localparam [2:0] DOOR_OPEN   = 3'b011;
    localparam [2:0] DOOR_CLOSED = 3'b100;

    localparam FLOOR_WIDTH =
        (NUM_FLOORS <= 2) ? 1 : $clog2(NUM_FLOORS);

    localparam TRAVEL_WIDTH =
        (TRAVEL_CYCLES <= 2) ? 1 : $clog2(TRAVEL_CYCLES);

    localparam DOOR_WIDTH =
        (DOOR_OPEN_TIME <= 2) ? 1 : $clog2(DOOR_OPEN_TIME);

    reg [2:0] state;
    reg [2:0] next_state;

    // Latched pending requests.
    reg [NUM_FLOORS-1:0] request_reg;
    reg [NUM_FLOORS-1:0] next_request_reg;

    // 1 = moving/upward scan, 0 = moving/downward scan.
    reg direction_reg;
    reg next_direction_reg;

    // Floor-to-floor movement counter.
    reg [TRAVEL_WIDTH-1:0] travel_counter;
    reg [TRAVEL_WIDTH-1:0] next_travel_counter;

    // Door-open hold counter.
    reg [DOOR_WIDTH-1:0] door_counter;
    reg [DOOR_WIDTH-1:0] next_door_counter;

    reg [$clog2(NUM_FLOORS)-1:0] next_current_floor;

    integer i;

    /*
     * Sequential logic
     *
     * Reset:
     *   IDLE, floor 0, and all requests cleared.
     *
     * All registers are updated only on the clock edge.
     */
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            request_reg    <= {NUM_FLOORS{1'b0}};
            direction_reg  <= 1'b1;
            travel_counter <= {TRAVEL_WIDTH{1'b0}};
            door_counter   <= {DOOR_WIDTH{1'b0}};
            current_floor  <= {FLOOR_WIDTH{1'b0}};
        end
        else begin
            state          <= next_state;
            request_reg    <= next_request_reg;
            direction_reg  <= next_direction_reg;
            travel_counter <= next_travel_counter;
            door_counter   <= next_door_counter;
            current_floor  <= next_current_floor;
        end
    end

    /*
     * Combinational next-state and Moore output logic.
     */
    always @(*) begin

        // Default values prevent inferred latches.
        next_state          = state;
        next_request_reg    = request_reg | floor_request;
        next_direction_reg  = direction_reg;
        next_travel_counter = travel_counter;
        next_door_counter   = door_counter;
        next_current_floor  = current_floor;

        // Moore outputs: depend only on current FSM state.
        motor_up       = 1'b0;
        motor_down     = 1'b0;
        door_open_out  = 1'b0;
        door_close_out = 1'b0;
        state_out      = state;

        case (state)

            // ---------------------------------------------------------
            // IDLE
            // If a request exists, choose the nearest requested floor.
            // ---------------------------------------------------------
            IDLE: begin
                next_travel_counter = {TRAVEL_WIDTH{1'b0}};

                // Current-floor request is serviced immediately.
                if (next_request_reg[current_floor]) begin
                    next_request_reg[current_floor] = 1'b0;
                    next_state = DOOR_OPEN;
                    next_door_counter = {DOOR_WIDTH{1'b0}};
                end

                // Search upward for the nearest request.
                else begin
                    for (i = 0; i < NUM_FLOORS; i = i + 1) begin
                        if ((i > current_floor) &&
                            next_request_reg[i]) begin
                            next_direction_reg = 1'b1;
                            next_state = MOVING_UP;
                        end
                    end

                    // If no request is above, search downward.
                    if (next_state == IDLE) begin
                        for (i = NUM_FLOORS-1; i >= 0; i = i - 1) begin
                            if ((i < current_floor) &&
                                next_request_reg[i]) begin
                                next_direction_reg = 1'b0;
                                next_state = MOVING_DOWN;
                            end
                        end
                    end
                end
            end

            // ---------------------------------------------------------
            // MOVING_UP
            // Move one floor after TRAVEL_CYCLES clock cycles.
            // Stop when a requested floor is reached.
            // ---------------------------------------------------------
            MOVING_UP: begin
                motor_up = 1'b1;

                // A request at the current floor is the target.
                if (next_request_reg[current_floor]) begin
                    if (travel_counter == TRAVEL_CYCLES-1) begin
                        next_request_reg[current_floor] = 1'b0;
                        next_state = DOOR_OPEN;
                        next_door_counter = {DOOR_WIDTH{1'b0}};
                        next_travel_counter = {TRAVEL_WIDTH{1'b0}};
                    end
                    else begin
                        next_travel_counter = travel_counter + 1'b1;
                    end
                end

                // Continue moving upward.
                else if (travel_counter == TRAVEL_CYCLES-1) begin
                    next_travel_counter = {TRAVEL_WIDTH{1'b0}};

                    if (current_floor < NUM_FLOORS-1) begin
                        next_current_floor = current_floor + 1'b1;
                    end
                    else begin
                        // Top floor reached; reverse if requests remain.
                        next_direction_reg = 1'b0;
                        next_state = MOVING_DOWN;
                    end
                end

                // Keep counting travel cycles.
                else begin
                    next_travel_counter = travel_counter + 1'b1;
                end
            end

            // ---------------------------------------------------------
            // MOVING_DOWN
            // Move one floor after TRAVEL_CYCLES clock cycles.
            // Stop when a requested floor is reached.
            // ---------------------------------------------------------
            MOVING_DOWN: begin
                motor_down = 1'b1;

                // A request at the current floor is the target.
                if (next_request_reg[current_floor]) begin
                    if (travel_counter == TRAVEL_CYCLES-1) begin
                        next_request_reg[current_floor] = 1'b0;
                        next_state = DOOR_OPEN;
                        next_door_counter = {DOOR_WIDTH{1'b0}};
                        next_travel_counter = {TRAVEL_WIDTH{1'b0}};
                    end
                    else begin
                        next_travel_counter = travel_counter + 1'b1;
                    end
                end

                // Continue moving downward.
                else if (travel_counter == TRAVEL_CYCLES-1) begin
                    next_travel_counter = {TRAVEL_WIDTH{1'b0}};

                    if (current_floor > 0) begin
                        next_current_floor = current_floor - 1'b1;
                    end
                    else begin
                        // Ground floor reached; reverse if requests remain.
                        next_direction_reg = 1'b1;
                        next_state = MOVING_UP;
                    end
                end

                // Keep counting travel cycles.
                else begin
                    next_travel_counter = travel_counter + 1'b1;
                end
            end

            // ---------------------------------------------------------
            // DOOR_OPEN
            // Hold the door open for DOOR_OPEN_TIME cycles.
            // ---------------------------------------------------------
            DOOR_OPEN: begin
                door_open_out = 1'b1;

                // Obstacle keeps/reopens the door.
                if (door_obstacle) begin
                    next_state = DOOR_OPEN;
                    next_door_counter = {DOOR_WIDTH{1'b0}};
                end

                // Door hold time expired.
                else if (door_counter == DOOR_OPEN_TIME-1) begin
                    next_door_counter = {DOOR_WIDTH{1'b0}};
                    next_state = DOOR_CLOSED;
                end

                // Continue holding the door open.
                else begin
                    next_door_counter = door_counter + 1'b1;
                end
            end

            // ---------------------------------------------------------
            // DOOR_CLOSED
            // Continue in the current direction if requests exist.
            // Otherwise reverse direction if opposite requests exist.
            // Otherwise return to IDLE.
            // ---------------------------------------------------------
            DOOR_CLOSED: begin
                door_close_out = 1'b1;

                if (direction_reg) begin
                    // Requests above current floor: continue upward.
                    if (|next_request_reg[current_floor+1:NUM_FLOORS-1]) begin
                        next_direction_reg = 1'b1;
                        next_state = MOVING_UP;
                        next_travel_counter = {TRAVEL_WIDTH{1'b0}};
                    end

                    // No request above: search below and reverse.
                    else begin
                        next_direction_reg = 1'b0;
                        next_state = MOVING_DOWN;
                        next_travel_counter = {TRAVEL_WIDTH{1'b0}};

                        // If no request exists anywhere, stay idle.
                        if (!|next_request_reg)
                            next_state = IDLE;
                    end
                end
                else begin
                    // Requests below current floor: continue downward.
                    if (|next_request_reg[0:current_floor-1]) begin
                        next_direction_reg = 1'b0;
                        next_state = MOVING_DOWN;
                        next_travel_counter = {TRAVEL_WIDTH{1'b0}};
                    end

                    // No request below: search above and reverse.
                    else begin
                        next_direction_reg = 1'b1;
                        next_state = MOVING_UP;
                        next_travel_counter = {TRAVEL_WIDTH{1'b0}};

                        // If no request exists anywhere, stay idle.
                        if (!|next_request_reg)
                            next_state = IDLE;
                    end
                end
            end

            // ---------------------------------------------------------
            // Invalid state recovery.
            // ---------------------------------------------------------
            default: begin
                next_state          = IDLE;
                next_request_reg    = {NUM_FLOORS{1'b0}};
                next_direction_reg  = 1'b1;
                next_travel_counter = {TRAVEL_WIDTH{1'b0}};
                next_door_counter   = {DOOR_WIDTH{1'b0}};
                next_current_floor  = {FLOOR_WIDTH{1'b0}};
            end

        endcase
    end

endmodule
