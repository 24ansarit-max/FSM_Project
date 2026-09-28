module parameterized_mac #(
    parameter int DATA_WIDTH = 8,
    parameter int GUARD_BITS = $clog2(DATA_WIDTH),
    parameter int ACC_WIDTH  = (2 * DATA_WIDTH) + GUARD_BITS
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
    // Parameter checks
    //============================================================
    initial begin
        if ((DATA_WIDTH != 8) && (DATA_WIDTH != 16))
            $error("DATA_WIDTH must be 8 or 16");

        if (ACC_WIDTH < (2 * DATA_WIDTH))
            $error("ACC_WIDTH is too small");
    end

    //============================================================
    // Internal widths
    //============================================================
    localparam int OPERAND_WIDTH = DATA_WIDTH + 1;
    localparam int PRODUCT_WIDTH = 2 * OPERAND_WIDTH;

    //============================================================
    // FSM
    //============================================================
    typedef enum logic [5:0] {
        IDLE       = 6'b000001,
        LOAD       = 6'b000010,
        MULTIPLY   = 6'b000100,
        ACCUMULATE = 6'b001000,
        SATURATE   = 6'b010000,
        DONE       = 6'b100000
    } state_t;

    state_t state;
    state_t next_state;

    //============================================================
    // Input registers
    //============================================================
    logic signed [OPERAND_WIDTH-1:0] A_reg;
    logic signed [OPERAND_WIDTH-1:0] B_reg;

    logic signed_mode_reg;
    logic last_reg;

    //============================================================
    // Registered multiplier result
    //============================================================
    (* use_dsp = "yes" *)
    logic signed [PRODUCT_WIDTH-1:0] product_reg;

    //============================================================
    // Accumulator
    //============================================================
    logic signed [ACC_WIDTH-1:0] accumulator;

    // Extended product and sum
    logic signed [ACC_WIDTH:0] product_ext;
    logic signed [ACC_WIDTH:0] sum_ext;

    //============================================================
    // Saturation limits
    //============================================================
    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MAX =
        {1'b0, {(ACC_WIDTH-1){1'b1}}};

    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MIN =
        {1'b1, {(ACC_WIDTH-1){1'b0}}};

    localparam logic [ACC_WIDTH-1:0] UNSIGNED_MAX =
        {ACC_WIDTH{1'b1}};

    logic signed [ACC_WIDTH:0] signed_max_ext;
    logic signed [ACC_WIDTH:0] signed_min_ext;

    //============================================================
    // Extended saturation constants
    //============================================================
    always_comb begin
        signed_max_ext =
            $signed({
                SIGNED_MAX[ACC_WIDTH-1],
                SIGNED_MAX
            });

        signed_min_ext =
            $signed({
                SIGNED_MIN[ACC_WIDTH-1],
                SIGNED_MIN
            });
    end

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

            //====================================================
            IDLE
            //====================================================
            IDLE: begin
                if (start)
                    next_state = LOAD;
                else
                    next_state = IDLE;
            end

            //====================================================
            // LOAD
            //====================================================
            LOAD: begin
                if (valid_in)
                    next_state = MULTIPLY;
                else
                    next_state = LOAD;
            end

            //====================================================
            // MULTIPLY
            //====================================================
            MULTIPLY: begin
                next_state = ACCUMULATE;
            end

            //====================================================
            // ACCUMULATE
            //====================================================
            ACCUMULATE: begin
                next_state = SATURATE;
            end

            //====================================================
            // SATURATE / OVERFLOW CHECK
            //====================================================
            SATURATE: begin
                if (last_reg)
                    next_state = DONE;
                else
                    next_state = LOAD;
            end

            //====================================================
            // DONE
            //====================================================
            DONE: begin
                if (start)
                    next_state = LOAD;
                else
                    next_state = IDLE;
            end

            //====================================================
            // Safety recovery
            //====================================================
            default: begin
                next_state = IDLE;
            end

        endcase

    end

    //============================================================
    // Product extension
    //============================================================
    always_comb begin

        product_ext = '0;

        if (signed_mode_reg) begin

            // Signed product: sign extend.
            product_ext =
                $signed(product_reg);

        end
        else begin

            // Unsigned product: zero extend.
            product_ext =
                $signed({
                    1'b0,
                    product_reg
                });

        end

    end

    //============================================================
    // Accumulator + product
    //============================================================
    always_comb begin

        sum_ext =
            $signed({
                accumulator[ACC_WIDTH-1],
                accumulator
            }) +
            product_ext;

    end

    //============================================================
    // Registered output handshake
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            acc_out   <= '0;
            valid_out <= 1'b0;
            done      <= 1'b0;
            busy      <= 1'b0;

        end
        else begin

            // Default: pulses are LOW.
            done      <= 1'b0;
            valid_out <= 1'b0;

            // DONE is a completion state, not a busy state.
            if (state == DONE) begin

                busy      <= 1'b0;
                done      <= 1'b1;
                valid_out <= 1'b1;

                acc_out   <= accumulator;

            end
            else if (state != IDLE) begin

                busy <= 1'b1;

            end
            else begin

                busy <= 1'b0;

            end

        end

    end

    //============================================================
    // Datapath registers
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            A_reg           <= '0;
            B_reg           <= '0;

            signed_mode_reg <= 1'b0;
            last_reg        <= 1'b0;

            product_reg     <= '0;
            accumulator     <= '0;

            overflow        <= 1'b0;
            saturated       <= 1'b0;

        end

        //========================================================
        // Clear accumulator
        //========================================================
        else if (clear_acc) begin

            accumulator <= '0;

            product_reg <= '0;

            A_reg <= '0;
            B_reg <= '0;

            last_reg  <= 1'b0;

            overflow  <= 1'b0;
            saturated <= 1'b0;

        end

        else begin

            case (state)

                //================================================
                // IDLE
                //================================================
                IDLE: begin

                    if (start) begin

                        accumulator <= '0;

                        overflow  <= 1'b0;
                        saturated <= 1'b0;

                        // Lock arithmetic mode for
                        // the complete sequence.
                        signed_mode_reg <= signed_mode;

                    end

                end

                //================================================
                // LOAD
                //================================================
                LOAD: begin

                    if (valid_in) begin

                        last_reg <= last;

                        if (signed_mode_reg) begin

                            // Sign-extend operands.
                            A_reg <= $signed({
                                A[DATA_WIDTH-1],
                                A
                            });

                            B_reg <= $signed({
                                B[DATA_WIDTH-1],
                                B
                            });

                        end
                        else begin

                            // Zero-extend operands.
                            A_reg <= $signed({
                                1'b0,
                                A
                            });

                            B_reg <= $signed({
                                1'b0,
                                B
                            });

                        end

                    end

                end

                //================================================
                // MULTIPLY
                //================================================
                MULTIPLY: begin

                    // Single shared multiplier.
                    // Registered product helps DSP inference
                    // and timing closure.
                    product_reg <= A_reg * B_reg;

                end

                //================================================
                // ACCUMULATE
                //================================================
                ACCUMULATE: begin

                    // Arithmetic is calculated combinationally.
                    // The actual update is performed in SATURATE.
                    //
                    // This state is intentionally present to
                    // separate the multiply and accumulation
                    // pipeline stages.

                end

                //================================================
                // SATURATE / OVERFLOW CHECK
                //================================================
                SATURATE: begin

                    if (signed_mode_reg) begin

                        // Positive signed overflow.
                        if (sum_ext > signed_max_ext) begin

                            accumulator <= SIGNED_MAX;

                            overflow  <= 1'b1;
                            saturated <= 1'b1;

                        end

                        // Negative signed overflow.
                        else if (sum_ext < signed_min_ext) begin

                            accumulator <= SIGNED_MIN;

                            overflow  <= 1'b1;
                            saturated <= 1'b1;

                        end

                        // No signed overflow.
                        else begin

                            accumulator <=
                                sum_ext[ACC_WIDTH-1:0];

                        end

                    end
                    else begin

                        // Unsigned overflow is represented by
                        // the extra bit.
                        if (sum_ext[ACC_WIDTH] == 1'b1) begin

                            accumulator <=
                                $signed(UNSIGNED_MAX);

                            overflow  <= 1'b1;
                            saturated <= 1'b1;

                        end
                        else begin

                            accumulator <=
                                sum_ext[ACC_WIDTH-1:0];

                        end

                    end

                end

                //================================================
                // DONE
                //================================================
                DONE: begin

                    // Optional back-to-back sequence.
                    //
                    // start is accepted here, but the new
                    // sequence enters LOAD on the next clock.

                    if (start) begin

                        accumulator <= '0;

                        overflow  <= 1'b0;
                        saturated <= 1'b0;

                        signed_mode_reg <= signed_mode;

                    end

                end

                //================================================
                // Safety recovery
                //================================================
                default: begin

                    A_reg           <= '0;
                    B_reg           <= '0;

                    product_reg     <= '0;
                    accumulator     <= '0;

                    signed_mode_reg <= 1'b0;
                    last_reg        <= 1'b0;

                    overflow  <= 1'b0;
                    saturated <= 1'b0;

                end

            endcase

        end

    end

endmodule
