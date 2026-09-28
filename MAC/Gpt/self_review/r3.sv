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
    // Parameter checking
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

    state_t state, next_state;

    //============================================================
    // Latched operands/control
    //============================================================
    logic signed [OPERAND_WIDTH-1:0] A_reg;
    logic signed [OPERAND_WIDTH-1:0] B_reg;

    logic signed_mode_reg;
    logic last_reg;

    //============================================================
    // Registered product
    //============================================================
    (* use_dsp = "yes" *)
    logic signed [PRODUCT_WIDTH-1:0] product_reg;

    //============================================================
    // Accumulator datapath
    //============================================================
    logic signed [ACC_WIDTH-1:0] accumulator;

    logic signed [ACC_WIDTH:0] product_ext;
    logic signed [ACC_WIDTH:0] add_result;

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
    // Extended saturation limits
    //============================================================
    always_comb begin
        signed_max_ext =
            $signed({
                1'b0,
                SIGNED_MAX
            });

        signed_min_ext =
            $signed({
                1'b1,
                SIGNED_MIN
            });
    end

    //============================================================
    // FSM state register
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

    //============================================================
    // Product extension
    //============================================================
    always_comb begin

        product_ext = '0;

        if (signed_mode_reg) begin

            // Signed product.
            product_ext = $signed(product_reg);

        end
        else begin

            // Unsigned product.
            product_ext = $signed({
                1'b0,
                product_reg
            });

        end

    end

    //============================================================
    // Accumulator addition
    //============================================================
    always_comb begin

        add_result =
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

            // Default pulse values.
            done      <= 1'b0;
            valid_out <= 1'b0;

            case (state)

                IDLE: begin
                    busy <= 1'b0;
                end

                LOAD,
                MULTIPLY,
                ACCUMULATE,
                SATURATE: begin
                    busy <= 1'b1;
                end

                DONE: begin

                    busy      <= 1'b0;
                    done      <= 1'b1;
                    valid_out <= 1'b1;
                    acc_out   <= accumulator;

                end

                default: begin
                    busy <= 1'b0;
                end

            endcase

        end

    end

    //============================================================
    // Datapath registers
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            A_reg           <= '0;
            B_reg           <= '0;
            product_reg     <= '0;
            accumulator     <= '0;

            signed_mode_reg <= 1'b0;
            last_reg        <= 1'b0;

            overflow        <= 1'b0;
            saturated       <= 1'b0;

        end
        else if (clear_acc) begin

            // Cancel the current transaction.
            A_reg       <= '0;
            B_reg       <= '0;
            product_reg <= '0;

            accumulator <= '0;

            last_reg    <= 1'b0;

            overflow    <= 1'b0;
            saturated   <= 1'b0;

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

                        // Lock mode for the complete sequence.
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

                            // Sign extension.
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

                            // Zero extension.
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
                    product_reg <= A_reg * B_reg;

                end

                //================================================
                // ACCUMULATE
                //================================================
                ACCUMULATE: begin

                    // The extended sum is calculated combinationally
                    // and registered here.
                    //
                    // Overflow is checked in SATURATE.
                    accumulator <=
                        add_result[ACC_WIDTH-1:0];

                end

                //================================================
                // SATURATE / OVERFLOW CHECK
                //================================================
                SATURATE: begin

                    if (signed_mode_reg) begin

                        // Positive signed overflow.
                        if (add_result > signed_max_ext) begin

                            accumulator <= SIGNED_MAX;
                            overflow    <= 1'b1;
                            saturated   <= 1'b1;

                        end

                        // Negative signed overflow.
                        else if (add_result < signed_min_ext) begin

                            accumulator <= SIGNED_MIN;
                            overflow    <= 1'b1;
                            saturated   <= 1'b1;

                        end
                        else begin

                            // No overflow.
                            accumulator <=
                                add_result[ACC_WIDTH-1:0];

                        end

                    end
                    else begin

                        // Unsigned overflow.
                        if (add_result[ACC_WIDTH] == 1'b1) begin

                            accumulator <=
                                $signed(UNSIGNED_MAX);

                            overflow  <= 1'b1;
                            saturated <= 1'b1;

                        end
                        else begin

                            accumulator <=
                                add_result[ACC_WIDTH-1:0];

                        end

                    end

                end

                //================================================
                // DONE
                //================================================
                DONE: begin

                    // New sequence may be started immediately
                    // after DONE.
                    if (start) begin

                        accumulator <= '0;

                        overflow  <= 1'b0;
                        saturated <= 1'b0;

                        signed_mode_reg <= signed_mode;

                    end

                end

                //================================================
                // Illegal state recovery
                //================================================
                default: begin

                    A_reg       <= '0;
                    B_reg       <= '0;
                    product_reg <= '0;
                    accumulator <= '0;

                    signed_mode_reg <= 1'b0;
                    last_reg        <= 1'b0;

                    overflow  <= 1'b0;
                    saturated <= 1'b0;

                end

            endcase

        end

    end

endmodule
