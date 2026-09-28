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
    localparam logic [3:0] ADD = 4'b0000;
    localparam logic [3:0] SUB = 4'b0001;
    localparam logic [3:0] AND_OP = 4'b0010;
    localparam logic [3:0] OR_OP  = 4'b0011;
    localparam logic [3:0] XOR_OP = 4'b0100;
    localparam logic [3:0] NOT_OP = 4'b0101;
    localparam logic [3:0] SLL = 4'b0110;
    localparam logic [3:0] SRL = 4'b0111;
    localparam logic [3:0] SRA = 4'b1000;
    localparam logic [3:0] SLT = 4'b1001;

    localparam int SHIFT_WIDTH = $clog2(WIDTH);

    logic [WIDTH-1:0] result_next;
    logic zero_next;
    logic carry_next;
    logic overflow_next;
    logic negative_next;

    logic [WIDTH:0] temp;

    logic signed [WIDTH-1:0] signed_A;
    logic signed [WIDTH-1:0] signed_B;

    assign signed_A = $signed(A);
    assign signed_B = $signed(B);

    //============================================================
    // Combinational ALU
    //============================================================
    always_comb begin

        result_next   = '0;
        carry_next    = 1'b0;
        overflow_next = 1'b0;
        temp          = '0;

        case (opcode)

            //====================================================
            // ADD
            //====================================================
            ADD: begin
                temp = {1'b0, A} + {1'b0, B};

                result_next = temp[WIDTH-1:0];
                carry_next  = temp[WIDTH];

                // Signed overflow
                overflow_next =
                    (~(A[WIDTH-1] ^ B[WIDTH-1])) &&
                    (result_next[WIDTH-1] ^ A[WIDTH-1]);
            end

            //====================================================
            // SUB
            //====================================================
            SUB: begin
                result_next = A - B;

                // Carry = 1 means no unsigned borrow
                carry_next = (A >= B);

                // Signed overflow
                overflow_next =
                    (A[WIDTH-1] ^ B[WIDTH-1]) &&
                    (result_next[WIDTH-1] ^ A[WIDTH-1]);
            end

            //====================================================
            // AND
            //====================================================
            AND_OP: begin
                result_next = A & B;
            end

            //====================================================
            // OR
            //====================================================
            OR_OP: begin
                result_next = A | B;
            end

            //====================================================
            // XOR
            //====================================================
            XOR_OP: begin
                result_next = A ^ B;
            end

            //====================================================
            // NOT
            //====================================================
            NOT_OP: begin
                result_next = ~A;
            end

            //====================================================
            // Logical Shift Left
            //====================================================
            SLL: begin
                result_next = A << B[$clog2(WIDTH)-1:0];
            end

            //====================================================
            // Logical Shift Right
            //====================================================
            SRL: begin
                result_next = A >> B[$clog2(WIDTH)-1:0];
            end

            //====================================================
            // Arithmetic Shift Right
            //====================================================
            SRA: begin
                result_next =
                    signed_A >>> B[$clog2(WIDTH)-1:0];
            end

            //====================================================
            // Signed Set-Less-Than
            //====================================================
            SLT: begin
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

        // Common flags
        zero_next     = (result_next == '0);
        negative_next = result_next[WIDTH-1];

    end

    //============================================================
    // Sequential output registers
    // Active-high synchronous reset
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
