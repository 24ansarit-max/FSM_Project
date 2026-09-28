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

    alu_op_t operation;

    // WIDTH = 16 -> SHIFT_WIDTH = 4
    // WIDTH = 32 -> SHIFT_WIDTH = 5
    localparam int SHIFT_WIDTH = $clog2(WIDTH);

    logic [SHIFT_WIDTH-1:0] shift_amount;

    assign operation    = alu_op_t'(op);
    assign shift_amount = b[SHIFT_WIDTH-1:0];

    //============================================================
    // Shared ADD/SUB datapath
    //
    // ADD: A + B
    // SUB: A + ~B + 1
    //
    // WIDTH+1 bits preserve the carry-out.
    //============================================================
    logic             subtract;
    logic [WIDTH-1:0] b_modified;
    logic [WIDTH:0]   addsub_result;

    assign subtract = (operation == OP_SUB);

    assign b_modified = b ^ {WIDTH{subtract}};

    assign addsub_result =
        {1'b0, a}
        + {1'b0, b_modified}
        + {{WIDTH{1'b0}}, subtract};

    //============================================================
    // Combinational result/flag signals
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

        // Default assignments prevent latch inference
        result_next   = {WIDTH{1'b0}};
        carry_next    = 1'b0;
        overflow_next = 1'b0;

        case (operation)

            OP_ADD: begin
                result_next = addsub_result[WIDTH-1:0];
                carry_next  = addsub_result[WIDTH];

                // Signed ADD overflow
                overflow_next =
                    (~(a[WIDTH-1] ^ b[WIDTH-1])) &
                    (result_next[WIDTH-1] ^ a[WIDTH-1]);
            end

            OP_SUB: begin
                result_next = addsub_result[WIDTH-1:0];

                // 1 = no unsigned borrow
                // 0 = unsigned borrow
                carry_next = addsub_result[WIDTH];

                // Signed SUB overflow
                overflow_next =
                    (a[WIDTH-1] ^ b[WIDTH-1]) &
                    (result_next[WIDTH-1] ^ a[WIDTH-1]);
            end

            OP_AND: begin
                result_next = a & b;
            end

            OP_OR: begin
                result_next = a | b;
            end

            OP_XOR: begin
                result_next = a ^ b;
            end

            OP_NOT: begin
                result_next = ~a;
            end

            OP_SLL: begin
                if (b >= WIDTH)
                    result_next = {WIDTH{1'b0}};
                else
                    result_next = a << shift_amount;
            end

            OP_SRL: begin
                if (b >= WIDTH)
                    result_next = {WIDTH{1'b0}};
                else
                    result_next = a >> shift_amount;
            end

            OP_SRA: begin
                if (b >= WIDTH)
                    result_next = {WIDTH{a[WIDTH-1]}};
                else
                    result_next = $signed(a) >>> shift_amount;
            end

            OP_SLT: begin
                if ($signed(a) < $signed(b))
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
