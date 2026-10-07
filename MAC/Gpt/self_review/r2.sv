`timescale 1ns/1ps

module parameterized_mac #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = (2 * DATA_WIDTH) + 16
)(
    input  clk,
    input  rst,
    input  start,
    input  clear_acc,

    input [DATA_WIDTH-1:0] A,
    input [DATA_WIDTH-1:0] B,

    input signed_mode,
    input valid_in,
    input last,

    output reg [ACC_WIDTH-1:0] acc_out,
    output reg valid_out,
    output reg done,
    output reg busy,
    output reg overflow,
    output reg saturated
);

    localparam PROD_WIDTH = 2 * DATA_WIDTH;

    // ---------------------------------------------------------
    // FSM STATES
    // ---------------------------------------------------------

    localparam IDLE       = 3'd0;
    localparam LOAD       = 3'd1;
    localparam MULTIPLY   = 3'd2;
    localparam ACCUMULATE = 3'd3;
    localparam SATURATE   = 3'd4;
    localparam DONE       = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;

    // ---------------------------------------------------------
    // REGISTERS
    // ---------------------------------------------------------

    reg [DATA_WIDTH-1:0] A_reg;
    reg [DATA_WIDTH-1:0] B_reg;

    reg [PROD_WIDTH-1:0] product_reg;

    reg [ACC_WIDTH-1:0] accumulator;

    reg signed_mode_reg;
    reg last_reg;

    reg overflow_reg;
    reg saturated_reg;

    // ---------------------------------------------------------
    // EXTENDED VALUES
    // ---------------------------------------------------------

    reg [ACC_WIDTH-1:0] product_unsigned_ext;
    reg signed [ACC_WIDTH-1:0] product_signed_ext;

    reg [ACC_WIDTH:0] unsigned_sum_ext;
    reg signed [ACC_WIDTH:0] signed_sum_ext;

    reg [ACC_WIDTH-1:0] accumulator_next;

    // ---------------------------------------------------------
    // CONSTANTS
    // ---------------------------------------------------------

    localparam [ACC_WIDTH-1:0] UNSIGNED_MAX =
        {ACC_WIDTH{1'b1}};

    localparam signed [ACC_WIDTH-1:0] SIGNED_MAX =
        {1'b0,{(ACC_WIDTH-1){1'b1}}};

    localparam signed [ACC_WIDTH-1:0] SIGNED_MIN =
        {1'b1,{(ACC_WIDTH-1){1'b0}}};


    // ---------------------------------------------------------
    // NEXT STATE LOGIC
    // ---------------------------------------------------------

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


    // ---------------------------------------------------------
    // BUSY OUTPUT
    // ---------------------------------------------------------

    always @(*) begin

        if ((state == IDLE) || (state == DONE))
            busy = 1'b0;
        else
            busy = 1'b1;

    end


    // ---------------------------------------------------------
    // EXTEND PRODUCT
    // ---------------------------------------------------------

    always @(*) begin

        product_unsigned_ext =
            {{(ACC_WIDTH-PROD_WIDTH){1'b0}},product_reg};

        product_signed_ext =
            {{(ACC_WIDTH-PROD_WIDTH){product_reg[PROD_WIDTH-1]}},
             product_reg};

    end


    // ---------------------------------------------------------
    // CALCULATE ACCUMULATOR NEXT VALUE
    // ---------------------------------------------------------

    always @(*) begin

        unsigned_sum_ext =
            {1'b0,accumulator} +
            {1'b0,product_unsigned_ext};

        signed_sum_ext =
            $signed({accumulator[ACC_WIDTH-1],accumulator}) +
            $signed({product_signed_ext[ACC_WIDTH-1],
                     product_signed_ext});

        if (signed_mode_reg)
            accumulator_next = signed_sum_ext[ACC_WIDTH-1:0];
        else
            accumulator_next = unsigned_sum_ext[ACC_WIDTH-1:0];

    end


    // ---------------------------------------------------------
    // MAIN SEQUENTIAL LOGIC
    // ---------------------------------------------------------

    always @(posedge clk) begin

        if (rst) begin

            state <= IDLE;

            A_reg <= 0;
            B_reg <= 0;
            product_reg <= 0;

            accumulator <= 0;

            signed_mode_reg <= 0;
            last_reg <= 0;

            overflow_reg <= 0;
            saturated_reg <= 0;

            acc_out <= 0;

            valid_out <= 0;
            done <= 0;

            overflow <= 0;
            saturated <= 0;

        end
        else begin

            state <= next_state;

            valid_out <= 0;
            done <= 0;

            // -------------------------------------------------
            // CLEAR ACCUMULATOR
            // -------------------------------------------------

            if (clear_acc &&
                (state != IDLE) &&
                (state != DONE)) begin

                accumulator <= 0;

                overflow_reg <= 0;
                saturated_reg <= 0;

                state <= LOAD;

            end
            else begin

                case (state)

                    // -----------------------------------------
                    // IDLE
                    // -----------------------------------------

                    IDLE: begin

                        if (start) begin

                            signed_mode_reg <= signed_mode;

                            accumulator <= 0;

                            overflow_reg <= 0;
                            saturated_reg <= 0;

                        end

                    end


                    // -----------------------------------------
                    // LOAD
                    // -----------------------------------------

                    LOAD: begin

                        if (valid_in) begin

                            A_reg <= A;
                            B_reg <= B;

                            last_reg <= last;

                        end

                    end


                    // -----------------------------------------
                    // MULTIPLY
                    // -----------------------------------------

                    MULTIPLY: begin

                        if (signed_mode_reg)
                            product_reg <=
                                $signed(A_reg) * $signed(B_reg);
                        else
                            product_reg <=
                                A_reg * B_reg;

                    end


                    // -----------------------------------------
                    // ACCUMULATE
                    // -----------------------------------------

                    ACCUMULATE: begin

                        accumulator <= accumulator_next;

                    end


                    // -----------------------------------------
                    // SATURATE
                    // -----------------------------------------

                    SATURATE: begin

                        if (signed_mode_reg) begin

                            if (signed_sum_ext > SIGNED_MAX) begin

                                accumulator <= SIGNED_MAX;

                                overflow_reg <= 1'b1;
                                saturated_reg <= 1'b1;

                            end
                            else if (signed_sum_ext < SIGNED_MIN) begin

                                accumulator <= SIGNED_MIN;

                                overflow_reg <= 1'b1;
                                saturated_reg <= 1'b1;

                            end

                        end
                        else begin

                            if (unsigned_sum_ext[ACC_WIDTH]) begin

                                accumulator <= UNSIGNED_MAX;

                                overflow_reg <= 1'b1;
                                saturated_reg <= 1'b1;

                            end

                        end

                    end


                    // -----------------------------------------
                    // DONE
                    // -----------------------------------------

                    DONE: begin

                        acc_out <= accumulator;

                        valid_out <= 1'b1;

                        done <= 1'b1;

                    end


                    // -----------------------------------------
                    // DEFAULT
                    // -----------------------------------------

                    default: begin

                        state <= IDLE;

                    end

                endcase

            end

            // -------------------------------------------------
            // OUTPUT STATUS
            // -------------------------------------------------

            overflow <= overflow_reg;
            saturated <= saturated_reg;

        end

    end

endmodule
