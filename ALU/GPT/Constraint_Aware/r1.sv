module parameterized_alu #(
    parameter int WIDTH = 16
)(
    input  logic             clk,
    input  logic             reset,

    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [3:0]       op,

    output logic [WIDTH-1:0] result,
    output logic             zero,
    output logic             carry,
    output logic             overflow,
    output logic             negative
);

    //============================================================
    // Parameter checks
    //============================================================
    initial begin
        if ((WIDTH != 16) && (WIDTH != 32))
            $error("WIDTH must be 16 or 32");
    end

    //============================================================
    // Opcode definition
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

    //============================================================
    // Shift amount
    // WIDTH=16 -> SHIFT_WIDTH=4
    // WIDTH=32 -> SHIFT_WIDTH=5
    //============================================================
    localparam int SHIFT_WIDTH = $clog2(WIDTH);

    logic [SHIFT_WIDTH-1:0] shift_amount;

    assign shift_amount = b[SHIFT_WIDTH-1:0];

    //============================================================
    // Shared ADD/SUB datapath
    //
    // ADD:
    //   a + b
    //
    // SUB:
    //   a + (~b) + 1
    //
    // The WIDTH+1 result allows Vivado to infer the FPGA
    // dedicated carry chain.
    //============================================================
    logic                 add_sub;
    logic [WIDTH-1:0]     b_addsub;
    logic [WIDTH:0]       addsub_ext;

    assign add_sub  = (op == OP_SUB);
    assign b_addsub = b ^ {WIDTH{add_sub}};

    assign addsub_ext =
        {1'b0, a} +
        {1'b0, b_addsub} +
        {{WIDTH{1'b0}}, add_sub};

    //============================================================
    // Combinational next-state signals
    //============================================================
    logic [WIDTH-1:0] result_next;
    logic             zero_next;
    logic             carry_next;
    logic             overflow_next;
    logic             negative_next;

    //============================================================
    // ALU combinational datapath
    //============================================================
    always_comb begin

        // Default assignments prevent latches
        result_next   = {WIDTH{1'b0}};
        carry_next    = 1'b0;
        overflow_next = 1'b0;

        case (op)

            //====================================================
            // ADD
            //====================================================
            OP_ADD: begin
                result_next = addsub_ext[WIDTH-1:0];
                carry_next  = addsub_ext[WIDTH];

                // Signed overflow:
                // Same-sign operands producing opposite-sign result
                overflow_next =
                    (~(a[WIDTH-1] ^ b[WIDTH-1])) &
                     (result_next[WIDTH-1] ^ a[WIDTH-1]);
            end

            //====================================================
            // SUB
            //====================================================
            OP_SUB: begin
                result_next = addsub_ext[WIDTH-1:0];

                // For two's-complement subtraction:
                // carry=1 -> no unsigned borrow
                // carry=0 -> unsigned borrow
                carry_next = addsub_ext[WIDTH];

                // Signed subtraction overflow:
                // Different-sign operands producing a result
                // whose sign differs from A
                overflow_next =
                    (a[WIDTH-1] ^ b[WIDTH-1]) &
                    (result_next[WIDTH-1] ^ a[WIDTH-1]);
            end

            //====================================================
            // AND
            //====================================================
            OP_AND: begin
                result_next = a & b;
            end

            //====================================================
            // OR
            //====================================================
            OP_OR: begin
                result_next = a | b;
            end

            //====================================================
            // XOR
            //====================================================
            OP_XOR: begin
                result_next = a ^ b;
            end

            //====================================================
            // NOT
            //====================================================
            OP_NOT: begin
                result_next = ~a;
            end

            //====================================================
            // Logical Shift Left
            //====================================================
            OP_SLL: begin
                if (b >= WIDTH)
                    result_next = {WIDTH{1'b0}};
                else
                    result_next = a << shift_amount;
            end

            //====================================================
            // Logical Shift Right
            //====================================================
            OP_SRL: begin
                if (b >= WIDTH)
                    result_next = {WIDTH{1'b0}};
                else
                    result_next = a >> shift_amount;
            end

            //====================================================
            // Arithmetic Shift Right
            //====================================================
            OP_SRA: begin
                if (b >= WIDTH)
                    result_next = {WIDTH{a[WIDTH-1]}};
                else
                    result_next = $signed(a) >>> shift_amount;
            end

            //====================================================
            // Signed Set-Less-Than
            //====================================================
            OP_SLT: begin
                if ($signed(a) < $signed(b))
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

        // Common flags
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
