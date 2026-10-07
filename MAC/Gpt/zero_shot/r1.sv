`timescale 1ns/1ps

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

    localparam int PROD_WIDTH = 2 * DATA_WIDTH;

    // ============================================================
    // Parameter checking
    // ============================================================

    initial begin
        if ((DATA_WIDTH != 8) && (DATA_WIDTH != 16))
            $error("DATA_WIDTH must be 8 or 16");

        if (ACC_WIDTH < PROD_WIDTH)
            $error("ACC_WIDTH must be >= 2*DATA_WIDTH");
    end


    // ============================================================
    // FSM
    // ============================================================

    typedef enum logic [2:0] {
        IDLE       = 3'd0,
        LOAD       = 3'd1,
        MULTIPLY   = 3'd2,
        ACCUMULATE = 3'd3,
        SATURATE   = 3'd4,
        DONE       = 3'd5
    } state_t;

    state_t state, next_state;


    // ============================================================
    // Registers
    // ============================================================

    logic [DATA_WIDTH-1:0] A_reg;
    logic [DATA_WIDTH-1:0] B_reg;

    logic [PROD_WIDTH-1:0] product_reg;

    logic [ACC_WIDTH-1:0] accumulator;

    logic signed_mode_reg;
    logic last_reg;

    logic overflow_reg;
    logic saturated_reg;


    // ============================================================
    // Arithmetic signals
    // ============================================================

    logic [ACC_WIDTH:0] unsigned_sum_ext;
    logic signed [ACC_WIDTH:0] signed_sum_ext;

    logic [ACC_WIDTH-1:0] product_unsigned_ext;
    logic signed [ACC_WIDTH-1:0] product_signed_ext;

    logic [ACC_WIDTH-1:0] accumulator_next;


    // ============================================================
    // Saturation constants
    // ============================================================

    localparam logic [ACC_WIDTH-1:0] UNSIGNED_MAX =
        {ACC_WIDTH{1'b1}};

    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MAX =
        {1'b0, {(ACC_WIDTH-1){1'b1}}};

    localparam logic signed [ACC_WIDTH-1:0] SIGNED_MIN =
        {1'b1, {(ACC_WIDTH-1){1'b0}}};


    // ============================================================
    // Next-state logic
    // ============================================================

    always @(*) begin

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


    // ============================================================
    // Busy
    // ============================================================

    always @(*) begin

        if ((state == IDLE) || (state == DONE))
            busy = 1'b0;
        else
            busy = 1'b1;

    end


    // ============================================================
    // Product extension
    // ============================================================

    always @(*) begin

        product_unsigned_ext =
            {{(ACC_WIDTH-PROD_WIDTH){1'b0}}, product_reg};

        product_signed_ext =
            {{(ACC_WIDTH-PROD_WIDTH){product_reg[PROD_WIDTH-1]}},
             product_reg};

    end


    // ============================================================
    // Calculate accumulator + product
    //
    // IMPORTANT:
    // This value is calculated BEFORE accumulator is updated.
    // SATURATE checks exactly this same value.
    // ============================================================

    always @(*) begin

        unsigned_sum_ext =
            {1'b0, accumulator} +
            {1'b0, product_unsigned_ext};

        signed_sum_ext =
            $signed({accumulator[ACC_WIDTH-1], accumulator}) +
            $signed({product_signed_ext[ACC_WIDTH-1],
                     product_signed_ext});

        if (signed_mode_reg)
            accumulator_next = signed_sum_ext[ACC_WIDTH-1:0];
        else
            accumulator_next = unsigned_sum_ext[ACC_WIDTH-1:0];

    end


    // ============================================================
    // Sequential controller + datapath
    // ============================================================

    always @(posedge clk) begin

        if (rst) begin

            state           <= IDLE;

            A_reg           <= '0;
            B_reg           <= '0;
            product_reg     <= '0;

            accumulator     <= '0;

            signed_mode_reg <= 1'b0;
            last_reg        <= 1'b0;

            overflow_reg    <= 1'b0;
            saturated_reg   <= 1'b0;

            acc_out         <= '0;
            valid_out       <= 1'b0;
            done            <= 1'b0;
            overflow        <= 1'b0;
            saturated       <= 1'b0;

        end
        else begin

            state <= next_state;

            // Default pulse outputs
            valid_out <= 1'b0;
            done      <= 1'b0;


            // ====================================================
            // CLEAR ACCUMULATOR
            // ====================================================

            if (clear_acc &&
                (state != IDLE) &&
                (state != DONE)) begin

                accumulator   <= '0;
                overflow_reg  <= 1'b0;
                saturated_reg <= 1'b0;

                state <= LOAD;

            end
            else begin

                case (state)

                    // =================================================
                    // IDLE
                    // =================================================

                    IDLE: begin

                        if (start) begin

                            signed_mode_reg <= signed_mode;

                            accumulator   <= '0;
                            overflow_reg  <= 1'b0;
                            saturated_reg <= 1'b0;

                        end

                    end


                    // =================================================
                    // LOAD
                    // =================================================

                    LOAD: begin

                        if (valid_in) begin

                            A_reg    <= A;
                            B_reg    <= B;
                            last_reg <= last;

                        end

                    end


                    // =================================================
                    // MULTIPLY
                    // =================================================

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


                    // =================================================
                    // ACCUMULATE
                    // =================================================

                    ACCUMULATE: begin

                        accumulator <= accumulator_next;

                    end


                    // =================================================
                    // SATURATE / OVERFLOW CHECK
                    // =================================================

                    SATURATE: begin

                        if (signed_mode_reg) begin

                            // Positive overflow
                            if (signed_sum_ext > SIGNED_MAX) begin

                                accumulator   <= SIGNED_MAX;
                                overflow_reg  <= 1'b1;
                                saturated_reg <= 1'b1;

                            end

                            // Negative overflow
                            else if (signed_sum_ext < SIGNED_MIN) begin

                                accumulator   <= SIGNED_MIN;
                                overflow_reg  <= 1'b1;
                                saturated_reg <= 1'b1;

                            end

                        end
                        else begin

                            // Unsigned overflow
                            if (unsigned_sum_ext[ACC_WIDTH]) begin

                                accumulator   <= UNSIGNED_MAX;
                                overflow_reg  <= 1'b1;
                                saturated_reg <= 1'b1;

                            end

                        end

                    end


                    // =================================================
                    // DONE
                    // =================================================

                    DONE: begin

                        acc_out   <= accumulator;
                        valid_out <= 1'b1;
                        done      <= 1'b1;

                    end


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
