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

    initial begin
        if ((DATA_WIDTH != 8) && (DATA_WIDTH != 16))
            $error("DATA_WIDTH must be 8 or 16");

        if (ACC_WIDTH < PROD_WIDTH)
            $error("ACC_WIDTH must be >= 2*DATA_WIDTH");
    end

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
    // Captured input registers
    //============================================================
    logic [DATA_WIDTH-1:0] A_reg;
    logic [DATA_WIDTH-1:0] B_reg;

    logic signed_mode_reg;
    logic last_reg;

    //============================================================
    // Product registers
    //============================================================
    logic [PROD_WIDTH-1:0]        product_unsigned;
    logic signed [PROD_WIDTH-1:0] product_signed;

    //============================================================
    // Accumulator
    //============================================================
    logic [ACC_WIDTH-1:0] accumulator;

    //============================================================
    // Status registers
    //============================================================
    logic overflow_reg;
    logic saturated_reg;

    //============================================================
    // Extended arithmetic values
    //============================================================
    logic [ACC_WIDTH:0] unsigned_sum_ext;
    logic signed [ACC_WIDTH:0] signed_sum_ext;

    logic [ACC_WIDTH-1:0] product_unsigned_ext;
    logic signed [ACC_WIDTH-1:0] product_signed_ext;

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
    // Busy generation
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
    // Product extension
    //============================================================
    always_comb begin

        // Unsigned product: zero extend
        product_unsigned_ext =
            {{(ACC_WIDTH-PROD_WIDTH){1'b0}},
             product_unsigned};

        // Signed product: sign extend
        product_signed_ext =
            {{(ACC_WIDTH-PROD_WIDTH){product_signed[PROD_WIDTH-1]}},
             product_signed};

    end

    //============================================================
    // Shared accumulation arithmetic
    //============================================================
    always_comb begin

        // Unsigned accumulation
        unsigned_sum_ext =
            {1'b0, accumulator} +
            {1'b0, product_unsigned_ext};

        // Signed accumulation
        signed_sum_ext =
            $signed({accumulator[ACC_WIDTH-1], accumulator}) +
            $signed({product_signed_ext[ACC_WIDTH-1],
                     product_signed_ext});

    end

    //============================================================
    // Sequential controller + datapath
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            state          <= IDLE;

            A_reg          <= {DATA_WIDTH{1'b0}};
            B_reg          <= {DATA_WIDTH{1'b0}};

            signed_mode_reg <= 1'b0;
            last_reg        <= 1'b0;

            product_unsigned <= {PROD_WIDTH{1'b0}};
            product_signed   <= {PROD_WIDTH{1'b0}};

            accumulator <= {ACC_WIDTH{1'b0}};

            overflow_reg  <= 1'b0;
            saturated_reg <= 1'b0;

            acc_out   <= {ACC_WIDTH{1'b0}};
            valid_out <= 1'b0;
            done      <= 1'b0;

            overflow  <= 1'b0;
            saturated <= 1'b0;

        end
        else begin

            state <= next_state;

            // One-cycle output pulses
            valid_out <= 1'b0;
            done      <= 1'b0;

            //====================================================
            // Clear accumulator
            //====================================================
            if (clear_acc) begin

                accumulator  <= {ACC_WIDTH{1'b0}};
                overflow_reg <= 1'b0;
                saturated_reg <= 1'b0;

                // If currently processing a sequence, restart
                // the input-waiting portion of the sequence.
                if (state != IDLE && state != DONE)
                    state <= LOAD;

            end
            else begin

                case (state)

                    //================================================
                    // IDLE
                    //================================================
                    IDLE: begin

                        if (start) begin

                            // Start a new accumulation sequence.
                            accumulator   <= {ACC_WIDTH{1'b0}};
                            overflow_reg  <= 1'b0;
                            saturated_reg <= 1'b0;

                            // Capture operation mode for this sequence.
                            signed_mode_reg <= signed_mode;

                        end

                    end

                    //================================================
                    // LOAD
                    //================================================
                    LOAD: begin

                        // valid_in low means wait here.
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

                            product_signed <=
                                $signed(A_reg) * $signed(B_reg);

                        end
                        else begin

                            product_unsigned <= A_reg * B_reg;

                        end

                    end

                    //================================================
                    // ACCUMULATE
                    //================================================
                    ACCUMULATE: begin

                        if (signed_mode_reg) begin

                            accumulator <=
                                signed_sum_ext[ACC_WIDTH-1:0];

                        end
                        else begin

                            accumulator <=
                                unsigned_sum_ext[ACC_WIDTH-1:0];

                        end

                    end

                    //================================================
                    // SATURATE / OVERFLOW CHECK
                    //================================================
                    SATURATE: begin

                        if (signed_mode_reg) begin

                            // Positive signed overflow
                            if (signed_sum_ext > SIGNED_MAX) begin

                                accumulator  <= SIGNED_MAX;
                                overflow_reg  <= 1'b1;
                                saturated_reg <= 1'b1;

                            end

                            // Negative signed overflow
                            else if (signed_sum_ext < SIGNED_MIN) begin

                                accumulator  <= SIGNED_MIN;
                                overflow_reg  <= 1'b1;
                                saturated_reg <= 1'b1;

                            end

                        end
                        else begin

                            // Unsigned overflow is the carry from
                            // the ACC_WIDTH-bit addition.
                            if (unsigned_sum_ext[ACC_WIDTH]) begin

                                accumulator  <= UNSIGNED_MAX;
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
                    // Safety recovery
                    //================================================
                    default: begin

                        state <= IDLE;

                    end

                endcase

            end

            // Export status
            overflow  <= overflow_reg;
            saturated <= saturated_reg;

        end

    end

endmodule
