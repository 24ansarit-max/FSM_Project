module alu #(
    parameter WIDTH = 16
) (
    input  logic             clk,
    input  logic             reset,
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [3:0]       op,

    output logic [WIDTH-1:0] y,
    output logic             zero,
    output logic             carry,
    output logic             overflow,
    output logic             negative
);

    // Opcode definitions
    localparam logic [3:0] OP_ADD = 4'b0000;
    localparam logic [3:0] OP_SUB = 4'b0001;
    localparam logic [3:0] OP_AND = 4'b0010;
    localparam logic [3:0] OP_OR  = 4'b0011;
    localparam logic [3:0] OP_XOR = 4'b0100;
    localparam logic [3:0] OP_NOT = 4'b0101;
    localparam logic [3:0] OP_SLL = 4'b0110;
    localparam logic [3:0] OP_SRL = 4'b0111;
    localparam logic [3:0] OP_SRA = 4'b1000;
    localparam logic [3:0] OP_SLT = 4'b1001;

    logic [WIDTH:0] temp;

    always_comb begin

        // Default values
        y        = '0;
        carry    = 1'b0;
        overflow = 1'b0;
        temp     = '0;

        case (op)

            // ADD
            OP_ADD: begin
                temp = {1'b0, a} + {1'b0, b};
                y = temp[WIDTH-1:0];
                carry = temp[WIDTH];

                // Signed overflow
                overflow =
                    (~(a[WIDTH-1] ^ b[WIDTH-1])) &
                    (y[WIDTH-1] ^ a[WIDTH-1]);
            end

            // SUB
            OP_SUB: begin
                y = a - b;

                // 1 = no unsigned borrow
                carry = (a >= b);

                // Signed overflow
                overflow =
                    (a[WIDTH-1] ^ b[WIDTH-1]) &
                    (y[WIDTH-1] ^ a[WIDTH-1]);
            end

            // AND
            OP_AND: begin
                y = a & b;
            end

            // OR
            OP_OR: begin
                y = a | b;
            end

            // XOR
            OP_XOR: begin
                y = a ^ b;
            end

            // NOT
            OP_NOT: begin
                y = ~a;
            end

            // Shift Left Logical
            OP_SLL: begin
                y = a << b;
            end

            // Logical Shift Right
            OP_SRL: begin
                y = a >> b;
            end

            // Arithmetic Shift Right
            OP_SRA: begin
                y = $signed(a) >>> b;
            end

            // Signed Set Less Than
            OP_SLT: begin
                if ($signed(a) < $signed(b))
                    y = {{(WIDTH-1){1'b0}}, 1'b1};
                else
                    y = '0;
            end

            // Default
            default: begin
                y        = '0;
                carry    = 1'b0;
                overflow = 1'b0;
            end

        endcase

        // Common flags
        zero     = (y == '0);
        negative = y[WIDTH-1];

    end

endmodule
