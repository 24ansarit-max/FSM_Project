module parameterized_alu #(
    parameter int WIDTH = 16
)(
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [3:0]       op,

    output logic [WIDTH-1:0] y,
    output logic             zero,
    output logic             carry,
    output logic             overflow,
    output logic             negative
);

    //============================================================
    // Opcode definitions
    //============================================================
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

    // Number of bits required for shift amount
    localparam int SHIFT_WIDTH = $clog2(WIDTH);

    // Extended arithmetic result
    logic [WIDTH:0] temp;

    // Shift amount
    logic [SHIFT_WIDTH-1:0] shift_amount;

    //============================================================
    // Shift amount
    //============================================================
    assign shift_amount = b[SHIFT_WIDTH-1:0];

    //============================================================
    // ALU
    //============================================================
    always_comb begin

        // Default values
        y        = '0;
        carry    = 1'b0;
        overflow = 1'b0;
        temp     = '0;

        case (op)

            //====================================================
            // ADD
            //====================================================
            OP_ADD: begin

                // Extra bit captures unsigned carry
                temp = {1'b0, a} + {1'b0, b};

                y     = temp[WIDTH-1:0];
                carry = temp[WIDTH];

                // Signed overflow:
                // Same-sign operands give opposite-sign result
                overflow =
                    (~(a[WIDTH-1] ^ b[WIDTH-1])) &
                     (y[WIDTH-1] ^ a[WIDTH-1]);
            end

            //====================================================
            // SUB
            //====================================================
            OP_SUB: begin

                // A - B = A + ~B + 1
                temp = {1'b0, a}
                      + {1'b0, ~b}
                      + {{WIDTH{1'b0}}, 1'b1};

                y = temp[WIDTH-1:0];

                // Carry = 1 means no unsigned borrow
                carry = temp[WIDTH];

                // Signed overflow:
                // Different-sign operands give result
                // with sign different from A
                overflow =
                    (a[WIDTH-1] ^ b[WIDTH-1]) &
                    (y[WIDTH-1] ^ a[WIDTH-1]);
            end

            //====================================================
            // AND
            //====================================================
            OP_AND: begin
                y = a & b;
            end

            //====================================================
            // OR
            //====================================================
            OP_OR: begin
                y = a | b;
            end

            //====================================================
            // XOR
            //====================================================
            OP_XOR: begin
                y = a ^ b;
            end

            //====================================================
            // NOT
            //====================================================
            OP_NOT: begin
                y = ~a;
            end

            //====================================================
            // Shift Left Logical
            //====================================================
            OP_SLL: begin

                if (b >= WIDTH)
                    y = '0;
                else
                    y = a << shift_amount;

            end

            //====================================================
            // Logical Shift Right
            //====================================================
            OP_SRL: begin

                if (b >= WIDTH)
                    y = '0;
                else
                    y = a >> shift_amount;

            end

            //====================================================
            // Arithmetic Shift Right
            //====================================================
            OP_SRA: begin

                if (b >= WIDTH)
                    y = {WIDTH{a[WIDTH-1]}};
                else
                    y = $signed(a) >>> shift_amount;

            end

            //====================================================
            // Signed Set Less Than
            //====================================================
            OP_SLT: begin

                if ($signed(a) < $signed(b))
                    y = {{(WIDTH-1){1'b0}}, 1'b1};
                else
                    y = '0;

            end

            //====================================================
            // Invalid opcode
            //====================================================
            default: begin
                y        = '0;
                carry    = 1'b0;
                overflow = 1'b0;
            end

        endcase

        //========================================================
        // Common flags
        //========================================================

        // Result is zero
        zero = (y == '0);

        // MSB represents sign in two's-complement
        negative = y[WIDTH-1];

    end

endmodule
