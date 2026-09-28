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

    // Operation codes
    localparam logic [3:0] ADD = 4'b0000;
    localparam logic [3:0] SUB = 4'b0001;
    localparam logic [3:0] AND = 4'b0010;
    localparam logic [3:0] OR  = 4'b0011;
    localparam logic [3:0] XOR = 4'b0100;
    localparam logic [3:0] NOT = 4'b0101;
    localparam logic [3:0] SLL = 4'b0110;
    localparam logic [3:0] SRL = 4'b0111;
    localparam logic [3:0] SRA = 4'b1000;
    localparam logic [3:0] SLT = 4'b1001;

    logic [WIDTH:0] temp;

    always_comb begin

        // Default values
        y        = '0;
        carry    = 1'b0;
        overflow = 1'b0;
        temp     = '0;

        case (op)

            // ADD
            ADD: begin
                temp = {1'b0, a} + {1'b0, b};
                y = temp[WIDTH-1:0];
                carry = temp[WIDTH];

                // Signed overflow
                overflow =
                    (~(a[WIDTH-1] ^ b[WIDTH-1])) &
                    (y[WIDTH-1] ^ a[WIDTH-1]);
            end

            // SUB
            SUB: begin
                y = a - b;

                // Carry = 1 means no unsigned borrow
                carry = (a >= b);

                // Signed overflow
                overflow =
                    (a[WIDTH-1] ^ b[WIDTH-1]) &
                    (y[WIDTH-1] ^ a[WIDTH-1]);
            end

            // AND
            AND: begin
                y = a & b;
            end

            // OR
            OR: begin
                y = a | b;
            end

            // XOR
            XOR: begin
                y = a ^ b;
            end

            // NOT
            NOT: begin
                y = ~a;
            end

            // Shift Left Logical
            SLL: begin
                y = a << b;
            end

            // Shift Right Logical
            SRL: begin
                y = a >> b;
            end

            // Shift Right Arithmetic
            SRA: begin
                y = $signed(a) >>> b;
            end

            // Signed Set Less Than
            SLT: begin
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
