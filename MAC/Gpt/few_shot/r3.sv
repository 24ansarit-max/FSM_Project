module parameterized_mac #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = (2 * DATA_WIDTH) + 16
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  start,
    input  logic                  clear_acc,

    input  logic [DATA_WIDTH-1:0] A,
    input  logic [DATA_WIDTH-1:0] B,

    input  logic                  signed_mode,
    input  logic                  valid_in,
    input  logic                  last,

    output logic [ACC_WIDTH-1:0]  acc_out,
    output logic                  valid_out,
    output logic                  done,
    output logic                  busy,
    output logic                  overflow,
    output logic                  saturated
);

    localparam int PROD_WIDTH = 2 * DATA_WIDTH;

    //============================================================
    // FSM
    //============================================================
    typedef enum logic [2:0] {
        IDLE       = 3'b000,
        LOAD       = 3'b001,
        MULTIPLY   = 3'b010,
        ACCUMULATE = 3'b011,
        SATURATE   = 3'b100,
        DONE       = 3'b101
    } state_t;

    state_t state, next_state;

    //============================================================
    // Datapath registers
    //============================================================
    logic [DATA_WIDTH-1:0] A_reg, B_reg;
    logic [PROD_WIDTH-1:0] product_reg;
    logic [ACC_WIDTH-1:0]  accumulator;

    logic signed_mode_reg;
    logic last_reg;

    //============================================================
    // Extended arithmetic
    //============================================================
    logic [ACC_WIDTH-1:0] product_ext;
    logic [ACC_WIDTH:0] unsigned_sum_ext;
    logic signed [ACC_WIDTH:0] signed_sum_ext;

    // Saturation limits
    localparam logic [ACC_WIDTH-1:0] UNSIGNED_MAX =
        {ACC_WIDTH{1'b1}};

    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MAX =
        {1'b0, {(ACC_WIDTH-1){1'b1}}};

    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MIN =
        {1'b1, {(ACC_WIDTH-1){1'b0}}};

    //============================================================
    // State register
    //============================================================
    always_ff @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    //============================================================
    // Next-state logic
    //============================================================
    always_comb begin
        next_state = state;

        case (state)

            IDLE: begin
                if (start)
                    next_state = LOAD;
            end

            LOAD: begin
                if (valid_in)
                    next_state = MULTIPLY;
            end

            MULTIPLY: begin
                next_state = ACCUMULATE;
            end

            ACCUMULATE: begin
                next_state = SATURATE;
            end

            SATURATE: begin
                if (last_reg)
                    next_state = DONE;
                else
                    next_state = LOAD;
            end

            DONE: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    //============================================================
    // Combinational datapath
    //============================================================
    always_comb begin

        product_ext = '0;

        if (signed_mode_reg) begin
            product_ext =
                {{(ACC_WIDTH-PROD_WIDTH){
                    product_reg[PROD_WIDTH-1]}},
                 product_reg};
        end
        else begin
            product_ext =
                {{(ACC_WIDTH-PROD_WIDTH){1'b0}},
                 product_reg};
        end

        unsigned_sum_ext =
            {1'b0, accumulator} +
            {1'b0, product_ext};

        signed_sum_ext =
            $signed({accumulator[ACC_WIDTH-1], accumulator}) +
            $signed({product_ext[ACC_WIDTH-1], product_ext});

    end

    //============================================================
    // Busy output
    //============================================================
    always_comb begin
        busy = 1'b1;

        case (state)
            IDLE,
            DONE: busy = 1'b0;

            default: busy = 1'b1;
        endcase
    end

    //============================================================
    // Datapath and outputs
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            A_reg           <= '0;
            B_reg           <= '0;
            product_reg     <= '0;
            accumulator     <= '0;

            signed_mode_reg <= 1'b0;
            last_reg        <= 1'b0;

            acc_out         <= '0;
            valid_out       <= 1'b0;
            done            <= 1'b0;
            overflow        <= 1'b0;
            saturated       <= 1'b0;

        end
        else begin

            // One-cycle output pulses
            valid_out <= 1'b0;
            done      <= 1'b0;

            //====================================================
            // Clear accumulator
            //====================================================
            if (clear_acc) begin

                accumulator <= '0;
                overflow    <= 1'b0;
                saturated   <= 1'b0;

                // Restart input sequence when clearing while busy.
                if ((state != IDLE) && (state != DONE))
                    state <= LOAD;

            end
            else begin

                case (state)

                    //================================================
                    // IDLE
                    //================================================
                    IDLE: begin
                        if (start) begin
                            accumulator <= '0;
                            overflow    <= 1'b0;
                            saturated   <= 1'b0;

                            signed_mode_reg <= signed_mode;
                        end
                    end

                    //================================================
                    // LOAD
                    //================================================
                    LOAD: begin
                        if (valid_in) begin
                            A_reg    <= A;
                            B_reg    <= B;
                            last_reg <= last;
                        end
                    end

                    //================================================
                    // MULTIPLY
                    //================================================
                    MULTIPLY: begin
                        if (signed_mode_reg)
                            product_reg <=
                                $signed(A_reg) * $signed(B_reg);
                        else
                            product_reg <= A_reg * B_reg;
                    end

                    //================================================
                    // ACCUMULATE
                    //================================================
                    ACCUMULATE: begin
                        // Sum is calculated in the combinational
                        // datapath and committed after overflow check.
                    end

                    //================================================
                    // SATURATE / OVERFLOW CHECK
                    //================================================
                    SATURATE: begin

                        if (signed_mode_reg) begin

                            if (signed_sum_ext > SIGNED_MAX) begin
                                accumulator <= SIGNED_MAX;
                                overflow    <= 1'b1;
                                saturated   <= 1'b1;
                            end
                            else if (signed_sum_ext < SIGNED_MIN) begin
                                accumulator <= SIGNED_MIN;
                                overflow    <= 1'b1;
                                saturated   <= 1'b1;
                            end
                            else begin
                                accumulator <=
                                    signed_sum_ext[ACC_WIDTH-1:0];
                            end

                        end
                        else begin

                            if (unsigned_sum_ext[ACC_WIDTH]) begin
                                accumulator <= UNSIGNED_MAX;
                                overflow    <= 1'b1;
                                saturated   <= 1'b1;
                            end
                            else begin
                                accumulator <=
                                    unsigned_sum_ext[ACC_WIDTH-1:0];
                            end

                        end

                    end

                    //================================================
                    // DONE
                    //================================================
                    DONE: begin
                        acc_out   <= accumulator;
                        valid_out <= 1'b1;
                        done      <= 1'b1;
                    end

                    //================================================
                    // Safety recovery
                    //================================================
                    default: begin
                        state <= IDLE;
                    end

                endcase

            end
        end
    end

endmodule
