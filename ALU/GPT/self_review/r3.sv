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
    typedef enum logic [3:0] {
        OP_ADD = 4'b0000,
        OP_SUB = 4'b0001,
        OP_AND = 4'b0010,
        OP_OR  = 4'b0011,
        OP_XOR = 4'b0100,
        OP_NOT = 4'b0101,
        OP_SLL = 4'b0110,
        OP_SRL = 4'b0111,
        OP_SRA = 4'b1000,
        OP_SLT = 4'b1001
    } alu_op_t;

    alu_op_t op;

    //============================================================
    // Parameterized shift amount
    // WIDTH=16 -> 4 bits
    // WIDTH=32 -> 5 bits
    //============================================================
    localparam int SHIFT_WIDTH = $clog2(WIDTH);

    // Explicit WIDTH-sized constant
    localparam logic [WIDTH-1:0] SHIFT_LIMIT = WIDTH'(WIDTH);

    logic [SHIFT_WIDTH-1:0] shift_amount;

    assign op           = alu_op_t'(opcode);
    assign shift_amount = B[SHIFT_WIDTH-1:0];

    //============================================================
    // Shared ADD/SUB datapath
    //============================================================
    logic             subtract;
    logic [WIDTH-1:0] B_modified;
    logic [WIDTH:0]   addsub_result;

    assign subtract = (op == OP_SUB);

    // ADD -> B
    // SUB -> ~B
    assign B_modified = B ^ {WIDTH{subtract}};

    // ADD: A + B + 0
    // SUB: A + ~B + 1
    assign addsub_result =
        {1'b0, A} +
        {1'b0, B_modified} +
        {{WIDTH{1'b0}}, subtract};

    //============================================================
    // Combinational next-state signals
    //============================================================
    logic [WIDTH-1:0] result_next;
    logic             zero_next;
    logic             carry_next;
    logic             overflow_next;
    logic             negative_next;

    //============================================================
    // ALU combinational logic
    //============================================================
    always_comb begin

        // Safe defaults
        result_next   = {WIDTH{1'b0}};
        carry_next    = 1'b0;
        overflow_next = 1'b0;

        case (op)

            //====================================================
            // ADD
            //====================================================
            OP_ADD: begin
                result_next = addsub_result[WIDTH-1:0];
                carry_next  = addsub_result[WIDTH];

                overflow_next =
                    (~(A[WIDTH-1] ^ B[WIDTH-1])) &
                    (result_next[WIDTH-1] ^ A[WIDTH-1]);
            end

            //====================================================
            // SUB
            //====================================================
            OP_SUB: begin
                result_next = addsub_result[WIDTH-1:0];

                // Carry = 1 -> no borrow
                // Carry = 0 -> borrow
                carry_next = addsub_result[WIDTH];

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
            // Shift Left Logical
            //====================================================
            OP_SLL: begin
                if (B >= SHIFT_LIMIT)
                    result_next = {WIDTH{1'b0}};
                else
                    result_next = A << shift_amount;
            end

            //====================================================
            // Logical Shift Right
            //====================================================
            OP_SRL: begin
                if (B >= SHIFT_LIMIT)
                    result_next = {WIDTH{1'b0}};
                else
                    result_next = A >> shift_amount;
            end

            //====================================================
            // Arithmetic Shift Right
            //====================================================
            OP_SRA: begin
                if (B >= SHIFT_LIMIT)
                    result_next = {WIDTH{A[WIDTH-1]}};
                else
                    result_next = $signed(A) >>> shift_amount;
            end

            //====================================================
            // Signed Set-Less-Than
            //====================================================
            OP_SLT: begin
                if ($signed(A) < $signed(B))
                    result_next = {{(WIDTH-1){1'b0}}, 1'b1};
                else
                    result_next = {WIDTH{1'b0}};
            end

            //====================================================
            // Undefined opcode
            //====================================================
            default: begin
                result_next   = {WIDTH{1'b0}};
                carry_next    = 1'b0;
                overflow_next = 1'b0;
            end

        endcase

        // Final-result flags
        zero_next     = (result_next == {WIDTH{1'b0}});
        negative_next = result_next[WIDTH-1];

    end

    //============================================================
    // Registered output stage
    // Synchronous active-high reset
    //============================================================
    always_ff @(posedge clk) begin

        if (reset) begin
            result   <= {WIDTH{1'b0}};
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
