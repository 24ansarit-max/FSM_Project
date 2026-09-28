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

    // WIDTH=16 -> 4 bits
    // WIDTH=32 -> 5 bits
    localparam int SHIFT_WIDTH = $clog2(WIDTH);

    logic [SHIFT_WIDTH-1:0] shift_amount;

    // Shared ADD/SUB datapath
    logic             subtract;
    logic [WIDTH-1:0] B_modified;
    logic [WIDTH:0]   addsub_result;

    // Combinational outputs before registering
    logic [WIDTH-1:0] result_next;
    logic             zero_next;
    logic             carry_next;
    logic             overflow_next;
    logic             negative_next;

    assign op = alu_op_t'(opcode);

    assign shift_amount = B[SHIFT_WIDTH-1:0];

    assign subtract = (op == OP_SUB);

    // SUB = A + (~B) + 1
    assign B_modified = B ^ {WIDTH{subtract}};

    // Shared arithmetic datapath
    assign addsub_result =
        {1'b0, A} +
        {1'b0, B_modified} +
        {{WIDTH{1'b0}}, subtract};

    //============================================================
    // Combinational ALU
    //============================================================
    always_comb begin

        result_next   = {WIDTH{1'b0}};
        carry_next    = 1'b0;
        overflow_next = 1'b0;

        case (op)

            OP_ADD: begin
                result_next = addsub_result[WIDTH-1:0];
                carry_next  = addsub_result[WIDTH];

                overflow_next =
                    (~(A[WIDTH-1] ^ B[WIDTH-1])) &
                    (result_next[WIDTH-1] ^ A[WIDTH-1]);
            end

            OP_SUB: begin
                result_next = addsub_result[WIDTH-1:0];

                // 1 = no borrow
                // 0 = borrow
                carry_next = addsub_result[WIDTH];

                overflow_next =
                    (A[WIDTH-1] ^ B[WIDTH-1]) &
                    (result_next[WIDTH-1] ^ A[WIDTH-1]);
            end

            OP_AND: begin
                result_next = A & B;
            end

            OP_OR: begin
                result_next = A | B;
            end

            OP_XOR: begin
                result_next = A ^ B;
            end

            OP_NOT: begin
                result_next = ~A;
            end

            OP_SLL: begin
                if (B >= WIDTH)
                    result_next = {WIDTH{1'b0}};
                else
                    result_next = A << shift_amount;
            end

            OP_SRL: begin
                if (B >= WIDTH)
                    result_next = {WIDTH{1'b0}};
                else
                    result_next = A >> shift_amount;
            end

            OP_SRA: begin
                if (B >= WIDTH)
                    result_next = {WIDTH{A[WIDTH-1]}};
                else
                    result_next = $signed(A) >>> shift_amount;
            end

            OP_SLT: begin
                if ($signed(A) < $signed(B))
                    result_next = {{(WIDTH-1){1'b0}}, 1'b1};
                else
                    result_next = {WIDTH{1'b0}};
            end

            default: begin
                result_next   = {WIDTH{1'b0}};
                carry_next    = 1'b0;
                overflow_next = 1'b0;
            end

        endcase

        zero_next     = (result_next == {WIDTH{1'b0}});
        negative_next = result_next[WIDTH-1];

    end

    //============================================================
    // Registered outputs
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
