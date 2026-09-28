module parameterized_mac #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = (2 * DATA_WIDTH) + 16
)(
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     start,
    input  logic                     clear_acc,

    input  logic [DATA_WIDTH-1:0]    A,
    input  logic [DATA_WIDTH-1:0]    B,

    input  logic                     signed_mode,
    input  logic                     valid_in,
    input  logic                     last,

    output logic [ACC_WIDTH-1:0]     acc_out,
    output logic                     valid_out,
    output logic                     done,
    output logic                     busy,
    output logic                     overflow,
    output logic                     saturated
);

    //============================================================
    // Derived parameters
    //============================================================
    localparam int PROD_WIDTH = 2 * DATA_WIDTH;

    // ACC_WIDTH must be large enough to contain one full product.
    initial begin
        if ((DATA_WIDTH != 8) && (DATA_WIDTH != 16))
            $error("DATA_WIDTH must be 8 or 16");

        if (ACC_WIDTH < PROD_WIDTH)
            $error("ACC_WIDTH must be >= 2*DATA_WIDTH");
    end

    //============================================================
    // FSM states
    //============================================================
    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        LOAD      = 3'b001,
        MULTIPLY  = 3'b010,
        ACCUMULATE = 3'b011,
        SATURATE  = 3'b100,
        DONE      = 3'b101
    } state_t;

    state_t state, next_state;

    //============================================================
    // Datapath registers
    //============================================================
    logic [DATA_WIDTH-1:0] A_reg;
    logic [DATA_WIDTH-1:0] B_reg;

    logic [PROD_WIDTH-1:0] product_reg;

    logic [ACC_WIDTH-1:0] accumulator;

    // signed_mode is captured at the beginning of a sequence.
    logic signed_mode_reg;

    // last is captured with the input element.
    logic last_reg;

    // Overflow/saturation status
    logic overflow_reg;
    logic saturated_reg;

    //============================================================
    // Extended datapath values
    //============================================================
    logic [ACC_WIDTH:0] unsigned_acc_ext;
    logic signed [ACC_WIDTH:0] signed_acc_ext;

    logic [ACC_WIDTH-1:0] product_unsigned_ext;
    logic signed [ACC_WIDTH-1:0] product_signed_ext;

    logic [ACC_WIDTH-1:0] sum_unsigned;
    logic signed [ACC_WIDTH-1:0] sum_signed;

    //============================================================
    // Saturation constants
    //============================================================

    // Unsigned maximum:
    // 1111...1111
    localparam logic [ACC_WIDTH-1:0] UNSIGNED_MAX =
        {ACC_WIDTH{1'b1}};

    // Signed maximum:
    // 0111...1111
    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MAX =
        {1'b0, {(ACC_WIDTH-1){1'b1}}};

    // Signed minimum:
    // 1000...0000
    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MIN =
        {1'b1, {(ACC_WIDTH-1){1'b0}}};

    //============================================================
    // State-dependent status
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
    // FSM next-state logic
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
    // Extended product
    //============================================================
    always_comb begin

        product_unsigned_ext =
            {{(ACC_WIDTH-PROD_WIDTH){1'b0}}, product_reg};

        product_signed_ext =
            {{(ACC_WIDTH-PROD_WIDTH){product_reg[PROD_WIDTH-1]}},
             product_reg};

    end

    //============================================================
    // Accumulation arithmetic
    //============================================================
    always_comb begin

        unsigned_acc_ext = {1'b0, accumulator}
                          + {1'b0, product_unsigned_ext};

        signed_acc_ext = $signed({accumulator[ACC_WIDTH-1],
                                  accumulator})
                       + $signed({product_signed_ext[ACC_WIDTH-1],
                                  product_signed_ext});

        sum_unsigned = unsigned_acc_ext[ACC_WIDTH-1:0];

        sum_signed = signed_acc_ext[ACC_WIDTH-1:0];

    end

    //============================================================
    // Main sequential controller/datapath
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            state          <= IDLE;

            A_reg          <= {DATA_WIDTH{1'b0}};
            B_reg          <= {DATA_WIDTH{1'b0}};
            product_reg    <= {PROD_WIDTH{1'b0}};

            accumulator    <= {ACC_WIDTH{1'b0}};

            signed_mode_reg <= 1'b0;
            last_reg        <= 1'b0;

            overflow_reg   <= 1'b0;
            saturated_reg  <= 1'b0;

            acc_out        <= {ACC_WIDTH{1'b0}};
            valid_out      <= 1'b0;
            done           <= 1'b0;
            overflow       <= 1'b0;
            saturated      <= 1'b0;

        end
        else begin

            state <= next_state;

            // Default: output pulses are one clock wide.
            valid_out <= 1'b0;
            done      <= 1'b0;

            //====================================================
            // Clear accumulator
            //
            // clear_acc has priority while the unit is active.
            // The current element is discarded and the sequence
            // resumes from LOAD.
            //====================================================
            if (clear_acc && (state != IDLE) && (state != DONE)) begin

                accumulator   <= {ACC_WIDTH{1'b0}};
                overflow_reg  <= 1'b0;
                saturated_reg <= 1'b0;

                state <= LOAD;

            end
            else begin

                case (state)

                    //================================================
                    // IDLE
                    //================================================
                    IDLE: begin

                        if (start) begin

                            // Capture signed/unsigned mode for the
                            // complete accumulation sequence.
                            signed_mode_reg <= signed_mode;

                            // Start with a clean accumulation.
                            accumulator   <= {ACC_WIDTH{1'b0}};
                            overflow_reg  <= 1'b0;
                            saturated_reg <= 1'b0;

                        end

                    end

                    //================================================
                    // LOAD
                    //
                    // valid_in=0 simply causes the FSM to wait.
                    //================================================
                    LOAD: begin

                        if (valid_in) begin

                            A_reg   <= A;
                            B_reg   <= B;
                            last_reg <= last;

                        end

                    end

                    //================================================
                    // MULTIPLY
                    //================================================
                    MULTIPLY: begin

                        if (signed_mode_reg) begin

                            product_reg <=
                                $signed(A_reg) * $signed(B_reg);

                        end
                        else begin

                            product_reg <= A_reg * B_reg;

                        end

                    end

                    //================================================
                    // ACCUMULATE
                    //================================================
                    ACCUMULATE: begin

                        if (signed_mode_reg) begin

                            accumulator <= sum_signed;

                        end
                        else begin

                            accumulator <= sum_unsigned;

                        end

                    end

                    //================================================
                    // SATURATE / OVERFLOW CHECK
                    //================================================
                    SATURATE: begin

                        if (signed_mode_reg) begin

                            // Signed overflow:
                            // sum > positive maximum
                            // OR
                            // sum < negative minimum
                            if (signed_acc_ext > SIGNED_MAX) begin

                                accumulator   <= SIGNED_MAX;
                                overflow_reg  <= 1'b1;
                                saturated_reg <= 1'b1;

                            end
                            else if (signed_acc_ext < SIGNED_MIN) begin

                                accumulator   <= SIGNED_MIN;
                                overflow_reg  <= 1'b1;
                                saturated_reg <= 1'b1;

                            end

                        end
                        else begin

                            // Unsigned overflow is detected from
                            // the carry-out of the extended addition.
                            if (unsigned_acc_ext[ACC_WIDTH]) begin

                                accumulator   <= UNSIGNED_MAX;
                                overflow_reg  <= 1'b1;
                                saturated_reg <= 1'b1;

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
                    // Safety default
                    //================================================
                    default: begin

                        state <= IDLE;

                    end

                endcase

            end

            //========================================================
            // Export status flags
            //========================================================
            overflow  <= overflow_reg;
            saturated <= saturated_reg;

        end

    end

endmodule
