`timescale 1ns/1ps

module alu_tb;

    parameter WIDTH = 16;

    logic clk;
    logic reset;
    logic [WIDTH-1:0] a;
    logic [WIDTH-1:0] b;
    logic [3:0] op;

    logic [WIDTH-1:0] y;
    logic zero;
    logic carry;
    logic overflow;
    logic negative;

    // ------------------------------------------------
    // Operation codes
    // ------------------------------------------------
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

    integer pass_count = 0;
    integer fail_count = 0;

    // ------------------------------------------------
    // DUT
    // ------------------------------------------------
    alu #(
        .WIDTH(WIDTH)
    ) dut (
        .clk      (clk),
        .reset    (reset),
        .a        (a),
        .b        (b),
        .op       (op),
        .y        (y),
        .zero     (zero),
        .carry    (carry),
        .overflow (overflow),
        .negative (negative)
    );

    // ------------------------------------------------
    // Clock: 100 MHz
    // ------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------
    // Test task
    // ------------------------------------------------
    task automatic check_result (
        input logic [WIDTH-1:0] test_a,
        input logic [WIDTH-1:0] test_b,
        input logic [3:0]       test_op,
        input logic [WIDTH-1:0] expected_y,
        input logic             expected_carry,
        input logic             expected_overflow,
        input logic             expected_zero,
        input logic             expected_negative,
        input string            test_name
    );

        begin
            // Apply inputs
            @(negedge clk);

            a  = test_a;
            b  = test_b;
            op = test_op;

            // Wait for combinational settling
            #1;

            if ((y          === expected_y)        &&
                (carry      === expected_carry)   &&
                (overflow   === expected_overflow) &&
                (zero       === expected_zero)     &&
                (negative   === expected_negative)) begin

                $display("PASS: %-25s A=%h B=%h Y=%h",
                         test_name, test_a, test_b, y);

                pass_count = pass_count + 1;
            end
            else begin

                $display("FAIL: %-25s", test_name);
                $display("      A=%h B=%h OP=%b",
                         test_a, test_b, test_op);
                $display("      Expected: Y=%h C=%b V=%b Z=%b N=%b",
                         expected_y,
                         expected_carry,
                         expected_overflow,
                         expected_zero,
                         expected_negative);

                $display("      Actual:   Y=%h C=%b V=%b Z=%b N=%b",
                         y,
                         carry,
                         overflow,
                         zero,
                         negative);

                fail_count = fail_count + 1;
            end
        end

    endtask

    // ------------------------------------------------
    // Test sequence
    // ------------------------------------------------
    initial begin

        // Initial values
        reset = 1'b1;
        a     = '0;
        b     = '0;
        op    = ADD;

        // Reset
        @(posedge clk);
        #1;

        reset = 1'b0;

        $display("");
        $display("==========================================");
        $display("        ALU TESTBENCH START");
        $display("==========================================");
        $display("");

        // ==================================================
        // ADD TESTS
        // ==================================================

        check_result(
            16'h0005,
            16'h0003,
            ADD,
            16'h0008,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "ADD normal"
        );

        // Carry test
        check_result(
            16'hFFFF,
            16'h0001,
            ADD,
            16'h0000,
            1'b1,
            1'b0,
            1'b1,
            1'b0,
            "ADD carry"
        );

        // Signed positive overflow
        // 32767 + 1 = -32768
        check_result(
            16'h7FFF,
            16'h0001,
            ADD,
            16'h8000,
            1'b0,
            1'b1,
            1'b0,
            1'b1,
            "ADD signed overflow"
        );

        // Signed negative overflow
        // -32768 + (-1) = 32767
        check_result(
            16'h8000,
            16'hFFFF,
            ADD,
            16'h7FFF,
            1'b1,
            1'b1,
            1'b0,
            1'b0,
            "ADD negative overflow"
        );

        // ==================================================
        // SUB TESTS
        // ==================================================

        check_result(
            16'h0008,
            16'h0003,
            SUB,
            16'h0005,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "SUB normal"
        );

        // Borrow
        check_result(
            16'h0003,
            16'h0008,
            SUB,
            16'hFFFB,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SUB borrow"
        );

        // Equal values
        check_result(
            16'h1234,
            16'h1234,
            SUB,
            16'h0000,
            1'b1,
            1'b0,
            1'b1,
            1'b0,
            "SUB equal"
        );

        // Signed subtraction overflow
        // 32767 - (-1) = -32768
        check_result(
            16'h7FFF,
            16'hFFFF,
            SUB,
            16'h8000,
            1'b0,
            1'b1,
            1'b0,
            1'b1,
            "SUB signed overflow"
        );

        // ==================================================
        // LOGICAL OPERATIONS
        // ==================================================

        check_result(
            16'hAAAA,
            16'h5555,
            AND,
            16'h0000,
            1'b0,
            1'b0,
            1'b1,
            1'b0,
            "AND"
        );

        check_result(
            16'hAAAA,
            16'h5555,
            OR,
            16'hFFFF,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "OR"
        );

        check_result(
            16'hAAAA,
            16'h5555,
            XOR,
            16'hFFFF,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "XOR"
        );

        check_result(
            16'hAAAA,
            16'h0000,
            NOT,
            16'h5555,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "NOT"
        );

        // ==================================================
        // SHIFT OPERATIONS
        // ==================================================

        check_result(
            16'h0001,
            16'h0004,
            SLL,
            16'h0010,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLL"
        );

        check_result(
            16'h0010,
            16'h0002,
            SRL,
            16'h0004,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SRL"
        );

        // Arithmetic right shift
        // 0x8000 >> 2 = 0xE000
        check_result(
            16'h8000,
            16'h0002,
            SRA,
            16'hE000,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SRA negative"
        );

        // Positive arithmetic shift
        check_result(
            16'h4000,
            16'h0002,
            SRA,
            16'h1000,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SRA positive"
        );

        // ==================================================
        // SIGNED SLT
        // ==================================================

        // 5 < 10
        check_result(
            16'h0005,
            16'h000A,
            SLT,
            16'h0001,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLT 5 < 10"
        );

        // 10 < 5 -> false
        check_result(
            16'h000A,
            16'h0005,
            SLT,
            16'h0000,
            1'b0,
            1'b0,
            1'b1,
            1'b0,
            "SLT 10 < 5"
        );

        // -1 < 1
        check_result(
            16'hFFFF,
            16'h0001,
            SLT,
            16'h0001,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLT -1 < 1"
        );

        // -32768 < 32767
        check_result(
            16'h8000,
            16'h7FFF,
            SLT,
            16'h0001,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLT min < max"
        );

        // ==================================================
        // ZERO TEST
        // ==================================================

        check_result(
            16'h0000,
            16'h0000,
            ADD,
            16'h0000,
            1'b0,
            1'b0,
            1'b1,
            1'b0,
            "ZERO result"
        );

        // ==================================================
        // INVALID OPCODE
        // ==================================================

        check_result(
            16'h1234,
            16'h5678,
            4'b1111,
            16'h0000,
            1'b0,
            1'b0,
            1'b1,
            1'b0,
            "Invalid opcode"
        );

        // ==================================================
        // FINAL RESULT
        // ==================================================

        $display("");
        $display("==========================================");
        $display("           ALU TESTBENCH RESULT");
        $display("==========================================");
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display("******** ALL TESTS PASSED ********");
        else
            $display("******** SOME TESTS FAILED ********");

        $display("==========================================");

        $finish;
    end

endmodule
