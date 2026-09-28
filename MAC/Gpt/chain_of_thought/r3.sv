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

    //============================================================
    // Parameters
    //============================================================
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

    state_t state;
    state_t next_state;

    //============================================================
    // Input registers
    //============================================================
    logic [DATA_WIDTH-1:0] A_reg;
    logic [DATA_WIDTH-1:0] B_reg;

    logic signed_mode_reg;
    logic last_reg;

    //============================================================
    // Product register
    //============================================================
    logic [PROD_WIDTH-1:0] product_reg;

    //============================================================
    // Accumulator
    //============================================================
    logic [ACC_WIDTH-1:0] accumulator;

    //============================================================
    // Extended product
    //============================================================
    logic [ACC_WIDTH-1:0] product_ext;

    //============================================================
    // Extended sums
    //============================================================
    logic [ACC_WIDTH:0] unsigned_sum_ext;

    logic signed [ACC_WIDTH:0] signed_sum_ext;

    //============================================================
    // Saturation limits
    //============================================================
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

                if (start)
                    next_state = LOAD;
                else
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

        // Default assignment
        product_ext = '0;

        //========================================================
        // Product extension
        //========================================================
        if (signed_mode_reg) begin

            // Sign extension
            product_ext =
                {{(ACC_WIDTH-PROD_WIDTH){
                    product_reg[PROD_WIDTH-1]}},
                 product_reg};

        end
        else begin

            // Zero extension
            product_ext =
                {{(ACC_WIDTH-PROD_WIDTH){1'b0}},
                 product_reg};

        end

        //========================================================
        // Unsigned extended sum
        //========================================================
        unsigned_sum_ext =
            {1'b0, accumulator} +
            {1'b0, product_ext};

        //========================================================
        // Signed extended sum
        //========================================================
        signed_sum_ext =
            $signed({accumulator[ACC_WIDTH-1],
                     accumulator}) +
            $signed({product_ext[ACC_WIDTH-1],
                     product_ext});

    end

    //============================================================
    // Busy output
    //============================================================
    always_comb begin

        busy = 1'b1;

        case (state)

            IDLE: begin
                busy = 1'b0;
            end

            DONE: begin
                busy = 1'b0;
            end

            default: begin
                busy = 1'b1;
            end

        endcase

    end

    //============================================================
    // Datapath and output registers
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            A_reg           <= '0;
            B_reg           <= '0;

            signed_mode_reg <= 1'b0;
            last_reg        <= 1'b0;

            product_reg     <= '0;
            accumulator     <= '0;

            acc_out         <= '0;

            valid_out       <= 1'b0;
            done            <= 1'b0;
            overflow        <= 1'b0;
            saturated       <= 1'b0;

        end
        else begin

            // One-cycle pulses
            valid_out <= 1'b0;
            done      <= 1'b0;

            //====================================================
            // Clear accumulator
            //====================================================
            if (clear_acc) begin

                accumulator <= '0;
                overflow    <= 1'b0;
                saturated   <= 1'b0;

                // Restart input collection
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

                            // Lock mode for this sequence
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

                        if (signed_mode_reg) begin

                            product_reg <=
                                $signed(A_reg) *
                                $signed(B_reg);

                        end
                        else begin

                            product_reg <=
                                A_reg * B_reg;

                        end

                    end

                    //================================================
                    // ACCUMULATE
                    //================================================
                    ACCUMULATE: begin

                        // Sum is calculated combinationally.
                        // Accumulator update occurs only after
                        // overflow checking in SATURATE.

                    end

                    //================================================
                    // SATURATE / OVERFLOW CHECK
                    //================================================
                    SATURATE: begin

                        if (signed_mode_reg) begin

                            // Positive signed overflow
                            if (signed_sum_ext > SIGNED_MAX) begin

                                accumulator <= SIGNED_MAX;
                                overflow    <= 1'b1;
                                saturated   <= 1'b1;

                            end

                            // Negative signed overflow
                            else if (signed_sum_ext < SIGNED_MIN) begin

                                accumulator <= SIGNED_MIN;
                                overflow    <= 1'b1;
                                saturated   <= 1'b1;

                            end

                            // No signed overflow
                            else begin

                                accumulator <=
                                    signed_sum_ext[ACC_WIDTH-1:0];

                            end

                        end
                        else begin

                            // Unsigned overflow
                            if (unsigned_sum_ext[ACC_WIDTH]) begin

                                accumulator <= UNSIGNED_MAX;
                                overflow    <= 1'b1;
                                saturated   <= 1'b1;

                            end

                            // No unsigned overflow
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

                        // Allow back-to-back sequences
                        if (start) begin

                            accumulator <= '0;
                            overflow    <= 1'b0;
                            saturated   <= 1'b0;

                            signed_mode_reg <= signed_mode;

                        end

                    end

                    //================================================
                    // Default recovery
                    //================================================
                    default: begin

                        state <= IDLE;

                    end

                endcase

            end

        end

    end

endmodule
