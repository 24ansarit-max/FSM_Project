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
    // Parameter validation
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
    localparam int DSP_OP_WIDTH   = DATA_WIDTH + 1;
    localparam int DSP_PROD_WIDTH = 2 * DSP_OP_WIDTH;

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
    // Input/control registers
    //============================================================
    logic signed [DSP_OP_WIDTH-1:0] A_reg;
    logic signed [DSP_OP_WIDTH-1:0] B_reg;

    logic signed_mode_reg;
    logic last_reg;

    //============================================================
    // Registered multiplier output
    //============================================================
    (* use_dsp = "yes" *)
    logic signed [DSP_PROD_WIDTH-1:0] product_reg;

    //============================================================
    // Accumulator
    //============================================================
    logic signed [ACC_WIDTH-1:0] accumulator;

    // Extra bit is used for overflow detection.
    logic signed [ACC_WIDTH:0] sum_ext;

    // Extended product.
    logic signed [ACC_WIDTH:0] product_ext;

    //============================================================
    // Saturation constants
    //============================================================
    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MAX =
        {1'b0, {(ACC_WIDTH-1){1'b1}}};

    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MIN =
        {1'b1, {(ACC_WIDTH-1){1'b0}}};

    localparam logic [ACC_WIDTH-1:0] UNSIGNED_MAX =
        {ACC_WIDTH{1'b1}};

    // Extended saturation limits.
    logic signed [ACC_WIDTH:0] signed_max_ext;
    logic signed [ACC_WIDTH:0] signed_min_ext;

    always_comb begin

        signed_max_ext =
            $signed({SIGNED_MAX[ACC_WIDTH-1],
                     SIGNED_MAX});

        signed_min_ext =
            $signed({SIGNED_MIN[ACC_WIDTH-1],
                     SIGNED_MIN});

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

        // clear_acc cancels the current transaction.
        if (clear_acc) begin

            case (state)

                IDLE: begin
                    next_state = IDLE;
                end

                DONE: begin
                    next_state = IDLE;
                end

                default: begin
                    next_state = LOAD;
                end

            endcase

        end
        else begin

            case (state)

                IDLE: begin

                    if (start)
                        next_state = LOAD;
                    else
                        next_state = IDLE;

                end

                LOAD: begin

                    if (valid_in)
                        next_state = MULTIPLY;
                    else
                        next_state = LOAD;

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

    end

    //============================================================
    // Product extension
    //============================================================
    always_comb begin

        product_ext = '0;

        if (signed_mode_reg) begin

            // Signed product -> sign extension.
            product_ext =
                $signed(product_reg);

        end
        else begin

            // Unsigned product -> zero extension.
            product_ext =
                $signed({
                    1'b0,
                    product_reg
                });

        end

    end

    //============================================================
    // Extended accumulator sum
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
    // Registered handshake outputs
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            acc_out   <= '0;
            valid_out <= 1'b0;
            done      <= 1'b0;
            busy      <= 1'b0;

        end
        else begin

            // One-cycle pulse defaults.
            done      <= 1'b0;
            valid_out <= 1'b0;

            // Registered busy follows the active transaction.
            case (next_state)

                LOAD,
                MULTIPLY,
                ACCUMULATE,
                SATURATE: begin
                    busy <= 1'b1;
                end

                default: begin
                    busy <= 1'b0;
                end

            endcase

            // Final result is available during DONE.
            if (state == DONE) begin

                acc_out   <= accumulator;
                valid_out <= 1'b1;
                done      <= 1'b1;

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
        else if (clear_acc) begin

            // Cancel the current transaction.
            A_reg       <= '0;
            B_reg       <= '0;
            product_reg <= '0;

            accumulator <= '0;

            overflow    <= 1'b0;
            saturated   <= 1'b0;

            last_reg    <= 1'b0;

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

                        // Capture mode for entire sequence.
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

                    // One shared multiplier.
                    // Vivado can infer DSP48E1.
                    product_reg <= A_reg * B_reg;

                end

                //================================================
                // ACCUMULATE
                //================================================
                ACCUMULATE: begin

                    // The actual accumulator update is delayed
                    // until SATURATE so overflow can be checked.

                end

                //================================================
                // SATURATE / OVERFLOW CHECK
                //================================================
                SATURATE: begin

                    if (signed_mode_reg) begin

                        // Positive signed overflow.
                        if (sum_ext > signed_max_ext) begin

                            accumulator <= SIGNED_MAX;
                            overflow    <= 1'b1;
                            saturated   <= 1'b1;

                        end

                        // Negative signed overflow.
                        else if (sum_ext < signed_min_ext) begin

                            accumulator <= SIGNED_MIN;
                            overflow    <= 1'b1;
                            saturated   <= 1'b1;

                        end

                        // Valid signed result.
                        else begin

                            accumulator <=
                                sum_ext[ACC_WIDTH-1:0];

                        end

                    end
                    else begin

                        // Unsigned overflow.
                        //
                        // Because accumulator and product are
                        // non-negative, the extra bit represents
                        // carry-out beyond ACC_WIDTH.

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

                    // Normal DONE requires no datapath operation.

                    // For back-to-back operation, clear the
                    // accumulator for the new sequence.
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

                    overflow        <= 1'b0;
                    saturated       <= 1'b0;

                end

            endcase

        end

    end

endmodule
