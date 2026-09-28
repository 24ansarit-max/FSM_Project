module parameterized_alu #(
    parameter int WIDTH = 16
)(
    input  logic             clk,
    input  logic             reset,

    input  logic [WIDTH-1:0] A,
    input  logic [WIDTH-1:0] B,
    input  logic [3:0]       opcode,

    output logic [WIDTH-1:0] result,
    output logic             zero,
    output logic             carry,
    output logic             overflow,
    output logic             negative
);

    //============================================================
    // Opcode definitions
    //============================================================
    localparam logic [3:0] OP_ADD  = 4'b0000;
    localparam logic [3:0] OP_SUB  = 4'b0001;
    localparam logic [3:0] OP_AND  = 4'b0010;
    localparam logic [3:0] OP_OR   = 4'b0011;
    localparam logic [3:0] OP_XOR  = 4'b0100;
    localparam logic [3:0] OP_NOT  = 4'b0101;
    localparam logic [3:0] OP_SLL  = 4'b0110;
    localparam logic [3:0] OP_SRL  = 4'b0111;
    localparam logic [3:0] OP_SRA  = 4'b1000;
    localparam logic [3:0] OP_SLT  = 4'b1001;

    // Shift amount width
    localparam int SHIFT_WIDTH = $clog2(WIDTH);

    logic [WIDTH-1:0] result_next;
    logic             zero_next;
    logic             carry_next;
    logic             overflow_next;
    logic             negative_next;

    logic [WIDTH:0]   temp;

    logic signed [WIDTH-1:0] signed_A;
    logic signed [WIDTH-1:0] signed_B;

    logic [SHIFT_WIDTH-1:0] shift_amount;

    assign signed_A = $signed(A);
    assign signed_B = $signed(B);

    assign shift_amount = B[SHIFT_WIDTH-1:0];

    //============================================================
    // Combinational ALU
    //============================================================
    always_comb begin

        // Default values
        result_next   = '0;
        carry_next    = 1'b0;
        overflow_next = 1'b0;

        case (opcode)

            //====================================================
            // ADD
            //====================================================
            OP_ADD: begin
                temp = {1'b0, A} + {1'b0, B};

                result_next = temp[WIDTH-1:0];
                carry_next  = temp[WIDTH];

                // Signed overflow:
                // Positive + Positive = Negative
                // Negative + Negative = Positive
                overflow_next =
                    (~(A[WIDTH-1] ^ B[WIDTH-1])) &
                     (result_next[WIDTH-1] ^ A[WIDTH-1]);
            end

            //====================================================
            // SUB
            //====================================================
            OP_SUB: begin
                temp = {1'b0, A} - {1'b0, B};

                result_next = temp[WIDTH-1:0];

                // Carry = 1 means no borrow
                carry_next = (A >= B);

                // Signed overflow:
                // Positive - Negative = Negative
                // Negative - Positive = Positive
                overflow_next =
                    (A[WIDTH-1] ^ B[WIDTH-1]) &
                    (result_next[WIDTH-1] ^ A[WIDTH-1]);
            end

            //====================================================
            // AND
            //====================================================
            OP_AND: begin
                result_next = A & B;
            end

            //====================================================
            // OR
            //====================================================
            OP_OR: begin
                result_next = A | B;
            end

            //====================================================
            // XOR
            //====================================================
            OP_XOR: begin
                result_next = A ^ B;
            end

            //====================================================
            // NOT
            //====================================================
            OP_NOT: begin
                result_next = ~A;
            end

            //====================================================
            // Logical Shift Left
            //====================================================
            OP_SLL: begin
                result_next = A << shift_amount;
            end

            //====================================================
            // Logical Shift Right
            //====================================================
            OP_SRL: begin
                result_next = A >> shift_amount;
            end

            //====================================================
            // Arithmetic Shift Right
            //====================================================
            OP_SRA: begin
                result_next = signed_A >>> shift_amount;
            end

            //====================================================
            // Set Less Than - Signed
            //====================================================
            OP_SLT: begin
                if (signed_A < signed_B)
                    result_next = {{(WIDTH-1){1'b0}}, 1'b1};
                else
                    result_next = '0;
            end

            //====================================================
            // Invalid opcode
            //====================================================
            default: begin
                result_next   = '0;
                carry_next    = 1'b0;
                overflow_next = 1'b0;
            end

        endcase

        //========================================================
        // Common flags
        //========================================================

        // Zero flag
        zero_next = (result_next == '0);

        // Negative flag = MSB of result
        negative_next = result_next[WIDTH-1];

    end

    //============================================================
    // Registered outputs
    // Synchronous active-high reset
    //============================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            result   <= '0;
            zero     <= 1'b1;
            carry    <= 1'b0;
            overflow <= 1'b0;
            negative <= 1'b0;
        end
        else begin
            result   <= result_next;
            zero     <= zero_next;
            carry    <= carry_next;
            overflow <= overflow_next;
            negative <= negative_next;
        end
    end

endmodule
