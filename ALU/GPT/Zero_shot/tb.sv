// Code your testbench here
// or browse Examples
`timescale 1ns/1ps

module parameterized_alu_tb;

    parameter int WIDTH = 16;

    logic                 clk;
    logic                 reset;
    logic [WIDTH-1:0]     A;
    logic [WIDTH-1:0]     B;
    logic [3:0]           opcode;

    logic [WIDTH-1:0]     result;
    logic                 zero;
    logic                 carry;
    logic                 overflow;
    logic                 negative;

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

    //============================================================
    // DUT
    //============================================================
    parameterized_alu #(
        .WIDTH(WIDTH)
    ) dut (
        .clk      (clk),
        .reset    (reset),
        .A        (A),
        .B        (B),
        .opcode   (opcode),
        .result   (result),
        .zero     (zero),
        .carry    (carry),
        .overflow (overflow),
        .negative (negative)
    );

    //============================================================
    // Clock: 100 MHz
    //============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //============================================================
    // Task to apply and check an operation
    //============================================================
    task automatic test_operation(
        input logic [3:0]       op,
        input logic [WIDTH-1:0] a_in,
        input logic [WIDTH-1:0] b_in,
        input logic [WIDTH-1:0] expected_result,
        input logic              expected_zero,
        input logic              expected_carry,
        input logic              expected_overflow,
        input logic              expected_negative,
        input string             test_name
    );
    begin
        @(negedge clk);

        opcode = op;
        A      = a_in;
        B      = b_in;

        @(posedge clk);
        #1;

        if ((result   === expected_result) &&
            (zero     === expected_zero)   &&
            (carry    === expected_carry)  &&
            (overflow === expected_overflow) &&
            (negative === expected_negative)) begin

            $display("PASS: %s | A=%h B=%h Result=%h",
                     test_name, A, B, result);

        end
        else begin

            $display("FAIL: %s", test_name);
            $display("      A=%h B=%h", A, B);
            $display("      Expected: Result=%h Z=%b C=%b V=%b N=%b",
                     expected_result,
                     expected_zero,
                     expected_carry,
                     expected_overflow,
                     expected_negative);
            $display("      Actual:   Result=%h Z=%b C=%b V=%b N=%b",
                     result,
                     zero,
                     carry,
                     overflow,
                     negative);

        end
    end
    endtask

    //============================================================
    // Test sequence
    //============================================================
    initial begin

        // Initial values
        reset  = 1'b1;
        A      = '0;
        B      = '0;
        opcode = OP_ADD;

        // Reset
        @(posedge clk);
        @(posedge clk);

        reset = 1'b0;

        //========================================================
        // ADD
        //========================================================

        test_operation(
            OP_ADD,
            16'h0005,
            16'h0003,
            16'h0008,
            1'b0, 1'b0, 1'b0, 1'b0,
            "ADD 5 + 3"
        );

        // ADD carry
        test_operation(
            OP_ADD,
            16'hFFFF,
            16'h0001,
            16'h0000,
            1'b1, 1'b1, 1'b0, 1'b0,
            "ADD carry"
        );

        // Signed positive overflow: 32767 + 1 = -32768
        test_operation(
            OP_ADD,
            16'h7FFF,
            16'h0001,
            16'h8000,
            1'b0, 1'b0, 1'b1, 1'b1,
            "ADD signed positive overflow"
        );

        // Signed negative overflow: -32768 + -1 = 32767
        test_operation(
            OP_ADD,
            16'h8000,
            16'hFFFF,
            16'h7FFF,
            1'b0, 1'b1, 1'b1, 1'b0,
            "ADD signed negative overflow"
        );

        //========================================================
        // SUB
        //========================================================

        test_operation(
            OP_SUB,
            16'h0008,
            16'h0003,
            16'h0005,
            1'b0, 1'b1, 1'b0, 1'b0,
            "SUB 8 - 3"
        );

        // Subtraction with borrow
        test_operation(
            OP_SUB,
            16'h0003,
            16'h0008,
            16'hFFFB,
            1'b0, 1'b0, 1'b0, 1'b1,
            "SUB borrow"
        );

        // Signed positive overflow:
        // 32767 - (-1) = -32768
        test_operation(
            OP_SUB,
            16'h7FFF,
            16'hFFFF,
            16'h8000,
            1'b0, 1'b0, 1'b1, 1'b1,
            "SUB signed positive overflow"
        );

        // Signed negative overflow:
        // -32768 - 1 = 32767
        test_operation(
            OP_SUB,
            16'h8000,
            16'h0001,
            16'h7FFF,
            1'b0, 1'b1, 1'b1, 1'b0,
            "SUB signed negative overflow"
        );

        // A == B
        test_operation(
            OP_SUB,
            16'h1234,
            16'h1234,
            16'h0000,
            1'b1, 1'b1, 1'b0, 1'b0,
            "SUB equal operands"
        );

        //========================================================
        // LOGIC
        //========================================================

        test_operation(
            OP_AND,
            16'hAAAA,
            16'h5555,
            16'h0000,
            1'b1, 1'b0, 1'b0, 1'b0,
            "AND"
        );

        test_operation(
            OP_OR,
            16'hAAAA,
            16'h5555,
            16'hFFFF,
            1'b0, 1'b0, 1'b0, 1'b1,
            "OR"
        );

        test_operation(
            OP_XOR,
            16'hAAAA,
            16'h5555,
            16'hFFFF,
            1'b0, 1'b0, 1'b0, 1'b1,
            "XOR"
        );

        test_operation(
            OP_NOT,
            16'hAAAA,
            16'h0000,
            16'h5555,
            1'b0, 1'b0, 1'b0, 1'b0,
            "NOT"
        );

        //========================================================
        // SHIFTS
        //========================================================

        test_operation(
            OP_SLL,
            16'h0001,
            16'h0004,
            16'h0010,
            1'b0, 1'b0, 1'b0, 1'b0,
            "SLL"
        );

        test_operation(
            OP_SRL,
            16'h8000,
            16'h0004,
            16'h0800,
            1'b0, 1'b0, 1'b0, 1'b0,
            "SRL"
        );

        // Arithmetic shift:
        // 16'h8000 >>> 4 = 16'hF800
        test_operation(
            OP_SRA,
            16'h8000,
            16'h0004,
            16'hF800,
            1'b0, 1'b0, 1'b0, 1'b1,
            "SRA negative value"
        );

        // Arithmetic shift positive
        test_operation(
            OP_SRA,
            16'h4000,
            16'h0002,
            16'h1000,
            1'b0, 1'b0, 1'b0, 1'b0,
            "SRA positive value"
        );

        //========================================================
        // SIGNED SET LESS THAN
        //========================================================

        // 5 < 10
        test_operation(
            OP_SLT,
            16'h0005,
            16'h000A,
            16'h0001,
            1'b0, 1'b0, 1'b0, 1'b0,
            "SLT 5 < 10"
        );

        // 10 < 5 = false
        test_operation(
            OP_SLT,
            16'h000A,
            16'h0005,
            16'h0000,
            1'b1, 1'b0, 1'b0, 1'b0,
            "SLT 10 < 5"
        );

        // -1 < 1 = true
        test_operation(
            OP_SLT,
            16'hFFFF,
            16'h0001,
            16'h0001,
            1'b0, 1'b0, 1'b0, 1'b0,
            "SLT -1 < 1"
        );

        // 1 < -1 = false
        test_operation(
            OP_SLT,
            16'h0001,
            16'hFFFF,
            16'h0000,
            1'b1, 1'b0, 1'b0, 1'b0,
            "SLT 1 < -1"
        );

        // A == B
        test_operation(
            OP_SLT,
            16'h1234,
            16'h1234,
            16'h0000,
            1'b1, 1'b0, 1'b0, 1'b0,
            "SLT equal"
        );

        //========================================================
        // INVALID OPCODE
        //========================================================

        test_operation(
            4'b1111,
            16'h1234,
            16'h5678,
            16'h0000,
            1'b1, 1'b0, 1'b0, 1'b0,
            "Invalid opcode"
        );

        //========================================================
        // ALL ZEROS
        //========================================================

        test_operation(
            OP_ADD,
            16'h0000,
            16'h0000,
            16'h0000,
            1'b1, 1'b0, 1'b0, 1'b0,
            "ADD all zeros"
        );

        //========================================================
        // ALL ONES
        //========================================================

        test_operation(
            OP_AND,
            16'hFFFF,
            16'hFFFF,
            16'hFFFF,
            1'b0, 1'b0, 1'b0, 1'b1,
            "AND all ones"
        );

        $display("==============================================");
        $display("        ALU TESTBENCH COMPLETED");
        $display("==============================================");

        #20;
        $finish;

    end

endmodule
