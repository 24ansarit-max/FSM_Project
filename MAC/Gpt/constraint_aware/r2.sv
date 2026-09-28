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
    // Parameters / widths
    //============================================================
    localparam int PROD_WIDTH     = 2 * DATA_WIDTH;
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

    state_t state, next_state;

    //============================================================
    // Input / control registers
    //============================================================
    logic signed [DSP_OP_WIDTH-1:0] A_reg;
    logic signed [DSP_OP_WIDTH-1:0] B_reg;

    logic signed_mode_reg;
    logic last_reg;

    //============================================================
    // DSP multiplier pipeline
    //============================================================
    (* use_dsp = "yes" *)
    logic signed [DSP_PROD_WIDTH-1:0] product_reg;

    //============================================================
    // Accumulator pipeline
    //============================================================
    logic signed [ACC_WIDTH-1:0] accumulator;

    logic signed [ACC_WIDTH:0] mac_sum_reg;

    //============================================================
    // Extended product
    //============================================================
    logic signed [ACC_WIDTH:0] product_ext;

    //============================================================
    // Saturation limits
    //============================================================
    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MAX =
        {1'b0, {(ACC_WIDTH-1){1'b1}}};

    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MIN =
        {1'b1, {(ACC_WIDTH-1){1'b0}}};

    localparam logic [ACC_WIDTH-1:0] UNSIGNED_MAX =
        {ACC_WIDTH{1'b1}};

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
    // Product extension
    //============================================================
    always_comb begin

        product_ext = '0;

        if (signed_mode_reg) begin

            product_ext =
                $signed(product_reg);

        end
        else begin

            product_ext =
                $signed({
                    1'b0,
                    product_reg[DSP_PROD_WIDTH-1:0]
                });

        end

    end

    //============================================================
    // Registered output/control logic
    //============================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            acc_out   <= '0;
            valid_out <= 1'b0;
            done      <= 1'b0;
            busy      <= 1'b0;

        end
        else begin

            // Default registered handshake values
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
                    busy      <= 1'b0;
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
            signed_mode_reg <= 1'b0;
            last_reg        <= 1'b0;

            product_reg     <= '0;
            mac_sum_reg     <= '0;
            accumulator     <= '0;

            overflow        <= 1'b0;
            saturated       <= 1'b0;

        end
        else if (clear_acc) begin

            // Clear has priority over an in-flight accumulation.
            accumulator <= '0;
            mac_sum_reg <= '0;

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
                        overflow    <= 1'b0;
                        saturated   <= 1'b0;

                        // Lock arithmetic mode for the sequence.
                        signed_mode_reg <= signed_mode;

                    end

                end

                //================================================
                // LOAD
                //================================================
                LOAD: begin

                    if (valid_in) begin

                        last_reg <= last;

                        // One shared signed representation.
                        //
                        // Signed mode:
                        //   sign-extend A/B.
                        //
                        // Unsigned mode:
                        //   zero-extend A/B.
                        //
                        // The same multiplier is therefore used
                        // for both modes.

                        if (signed_mode_reg) begin

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

                    // Registered DSP multiplier stage.
                    product_reg <= A_reg * B_reg;

                end

                //================================================
                // ACCUMULATE
                //================================================
                ACCUMULATE: begin

                    // Shared accumulation datapath.
                    //
                    // The extra sign bit allows the following
                    // saturation stage to distinguish overflow.

                    mac_sum_reg <=
                        $signed({
                            accumulator[ACC_WIDTH-1],
                            accumulator
                        }) +
                        product_ext;

                end

                //================================================
                // SATURATE / OVERFLOW CHECK
                //================================================
                SATURATE: begin

                    if (signed_mode_reg) begin

                        // Positive overflow:
                        // valid positive result requires
                        // sign extension of 0.
                        if ((mac_sum_reg[ACC_WIDTH] == 1'b0) &&
                            (mac_sum_reg[ACC_WIDTH-1] == 1'b1)) begin

                            accumulator <= SIGNED_MAX;
                            overflow    <= 1'b1;
                            saturated   <= 1'b1;

                        end

                        // Negative overflow:
                        // valid negative result requires
                        // sign extension of 1.
                        else if ((mac_sum_reg[ACC_WIDTH] == 1'b1) &&
                                 (mac_sum_reg[ACC_WIDTH-1] == 1'b0)) begin

                            accumulator <= SIGNED_MIN;
                            overflow    <= 1'b1;
                            saturated   <= 1'b1;

                        end

                        else begin

                            accumulator <=
                                mac_sum_reg[ACC_WIDTH-1:0];

                        end

                    end
                    else begin

                        // Unsigned operands were zero-extended.
                        // Therefore the extra bit represents carry-out.

                        if (mac_sum_reg[ACC_WIDTH]) begin

                            accumulator <=
                                $signed(UNSIGNED_MAX);

                            overflow  <= 1'b1;
                            saturated <= 1'b1;

                        end
                        else begin

                            accumulator <=
                                mac_sum_reg[ACC_WIDTH-1:0];

                        end

                    end

                end

                //================================================
                // DONE
                //================================================
                DONE: begin

                    // acc_out/valid_out/done are handled by the
                    // registered output block.

                    // Back-to-back operation:
                    // the next state is LOAD when start is asserted.

                    if (start) begin

                        accumulator <= '0;
                        overflow    <= 1'b0;
                        saturated   <= 1'b0;

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
                    mac_sum_reg     <= '0;
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
