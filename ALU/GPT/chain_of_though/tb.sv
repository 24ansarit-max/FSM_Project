`timescale 1ns/1ps

module parameterized_alu_tb;

    parameter int WIDTH = 16;

    //============================================================
    // DUT signals
    //============================================================
    logic [WIDTH-1:0] a;
    logic [WIDTH-1:0] b;
    logic [3:0]       op;

    logic [WIDTH-1:0] y;
    logic             zero;
    logic             carry;
    logic             overflow;
    logic             negative;

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

    integer pass_count = 0;
    integer fail_count = 0;

    //============================================================
    // DUT
    //============================================================
    parameterized_alu #(
        .WIDTH(WIDTH)
    ) dut (
        .a        (a),
        .b        (b),
        .op       (op),
        .y        (y),
        .zero     (zero),
        .carry    (carry),
        .overflow (overflow),
        .negative (negative)
    );

    //============================================================
    // Self-checking task
    //============================================================
    task automatic check_result;

        input logic [WIDTH-1:0] expected_y;
        input logic              expected_zero;
        input logic              expected_carry;
        input logic              expected_overflow;
        input logic              expected_negative;
        input string             test_name;

        begin

            #1;

            if ((y        === expected_y)       &&
                (zero     === expected_zero)   &&
                (carry    === expected_carry)   &&
                (overflow === expected_overflow) &&
                (negative === expected_negative)) begin

                $display(
                    "PASS: %-30s A=%h B=%h Y=%h",
                    test_name, a, b, y
                );

                pass_count = pass_count + 1;

            end
            else begin

                $display("FAIL: %-30s", test_name);

                $display(
                    "      A=%h B=%h OP=%b",
                    a, b, op
                );

                $display(
                    "      Expected: Y=%h Z=%b C=%b V=%b N=%b",
                    expected_y,
                    expected_zero,
                    expected_carry,
                    expected_overflow,
                    expected_negative
                );

                $display(
                    "      Actual:   Y=%h Z=%b C=%b V=%b N=%b",
                    y,
                    zero,
                    carry,
                    overflow,
                    negative
                );

                fail_count = fail_count + 1;

            end

        end

    endtask

    //============================================================
    // TESTS
    //============================================================
    initial begin

        $display("");
        $display("======================================================");
        $display("       PARAMETERIZED ALU TESTBENCH");
        $display("       WIDTH = %0d");
        $display("======================================================");
        $display("");

        //========================================================
        // ADD TESTS
        //========================================================

        a  = 16'h0005;
        b  = 16'h0003;
        op = OP_ADD;

        check_result(
            16'h0008,  // Y
            1'b0,      // Zero
            1'b0,      // Carry
            1'b0,      // Overflow
            1'b0,      // Negative
            "ADD normal"
        );

        // 0xFFFF + 1 = 0x0000, carry = 1
        a  = 16'hFFFF;
        b  = 16'h0001;
        op = OP_ADD;

        check_result(
            16'h0000,
            1'b1,
            1'b1,
            1'b0,
            1'b0,
            "ADD unsigned carry"
        );

        // 32767 + 1 = -32768
        a  = 16'h7FFF;
        b  = 16'h0001;
        op = OP_ADD;

        check_result(
            16'h8000,
            1'b0,
            1'b0,
            1'b1,
            1'b1,
            "ADD positive overflow"
        );

        // -32768 + (-1) = 32767
        a  = 16'h8000;
        b  = 16'hFFFF;
        op = OP_ADD;

        check_result(
            16'h7FFF,
            1'b0,
            1'b1,
            1'b1,
            1'b0,
            "ADD negative overflow"
        );

        //========================================================
        // SUBTRACTION TESTS
        //========================================================

        a  = 16'h0008;
        b  = 16'h0003;
        op = OP_SUB;

        check_result(
            16'h0005,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            "SUB normal"
        );

        // 3 - 8 = FFFB, borrow occurs
        a  = 16'h0003;
        b  = 16'h0008;
        op = OP_SUB;

        check_result(
            16'hFFFB,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SUB unsigned borrow"
        );

        // Equal values
        a  = 16'h1234;
        b  = 16'h1234;
        op = OP_SUB;

        check_result(
            16'h0000,
            1'b1,
            1'b1,
            1'b0,
            1'b0,
            "SUB equal"
        );

        // 32767 - (-1) = -32768
        a  = 16'h7FFF;
        b  = 16'hFFFF;
        op = OP_SUB;

        check_result(
            16'h8000,
            1'b0,
            1'b0,
            1'b1,
            1'b1,
            "SUB positive overflow"
        );

        // -32768 - 1 = 32767
        a  = 16'h8000;
        b  = 16'h0001;
        op = OP_SUB;

        check_result(
            16'h7FFF,
            1'b0,
            1'b1,
            1'b1,
            1'b0,
            "SUB negative overflow"
        );

        //========================================================
        // AND
        //========================================================

        a  = 16'hAAAA;
        b  = 16'h5555;
        op = OP_AND;

        check_result(
            16'h0000,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "AND"
        );

        //========================================================
        // OR
        //========================================================

        a  = 16'hAAAA;
        b  = 16'h5555;
        op = OP_OR;

        check_result(
            16'hFFFF,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "OR"
        );

        //========================================================
        // XOR
        //========================================================

        a  = 16'hAAAA;
        b  = 16'h5555;
        op = OP_XOR;

        check_result(
            16'hFFFF,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "XOR"
        );

        //========================================================
        // NOT
        //========================================================

        a  = 16'hAAAA;
        b  = 16'h0000;
        op = OP_NOT;

        check_result(
            16'h5555,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "NOT"
        );

        //========================================================
        // SLL
        //========================================================

        a  = 16'h0001;
        b  = 16'h0004;
        op = OP_SLL;

        check_result(
            16'h0010,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLL by 4"
        );

        // SLL by 15
        a  = 16'h0001;
        b  = 16'h000F;
        op = OP_SLL;

        check_result(
            16'h8000,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SLL by 15"
        );

        // SLL >= WIDTH
        a  = 16'h1234;
        b  = 16'd16;
        op = OP_SLL;

        check_result(
            16'h0000,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "SLL by WIDTH"
        );

        //========================================================
        // SRL
        //========================================================

        a  = 16'h8000;
        b  = 16'h0002;
        op = OP_SRL;

        check_result(
            16'h2000,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SRL by 2"
        );

        // SRL >= WIDTH
        a  = 16'hFFFF;
        b  = 16'd16;
        op = OP_SRL;

        check_result(
            16'h0000,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "SRL by WIDTH"
        );

        //========================================================
        // SRA
        //========================================================

        // 0x8000 = -32768
        // -32768 >>> 2 = -8192 = E000
        a  = 16'h8000;
        b  = 16'h0002;
        op = OP_SRA;

        check_result(
            16'hE000,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SRA negative"
        );

        // Positive arithmetic shift
        a  = 16'h4000;
        b  = 16'h0002;
        op = OP_SRA;

        check_result(
            16'h1000,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SRA positive"
        );

        // SRA >= WIDTH on negative number
        a  = 16'h8000;
        b  = 16'd16;
        op = OP_SRA;

        check_result(
            16'hFFFF,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SRA negative by WIDTH"
        );

        // SRA >= WIDTH on positive number
        a  = 16'h4000;
        b  = 16'd16;
        op = OP_SRA;

        check_result(
            16'h0000,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "SRA positive by WIDTH"
        );

        //========================================================
        // SIGNED SLT
        //========================================================

        // 5 < 10
        a  = 16'h0005;
        b  = 16'h000A;
        op = OP_SLT;

        check_result(
            16'h0001,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLT 5 < 10"
        );

        // 10 < 5 = false
        a  = 16'h000A;
        b  = 16'h0005;
        op = OP_SLT;

        check_result(
            16'h0000,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "SLT 10 < 5"
        );

        // -1 < 1
        a  = 16'hFFFF;
        b  = 16'h0001;
        op = OP_SLT;

        check_result(
            16'h0001,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLT -1 < 1"
        );

        // -32768 < 32767
        a  = 16'h8000;
        b  = 16'h7FFF;
        op = OP_SLT;

        check_result(
            16'h0001,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLT MIN < MAX"
        );

        // 32767 < -32768 = false
        a  = 16'h7FFF;
        b  = 16'h8000;
        op = OP_SLT;

        check_result(
            16'h0000,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "SLT MAX < MIN"
        );

        //========================================================
        // INVALID OPCODE
        //========================================================

        a  = 16'h1234;
        b  = 16'h5678;
        op = 4'b1111;

        check_result(
            16'h0000,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "Invalid opcode"
        );

        //========================================================
        // FINAL REPORT
        //========================================================

        $display("");
        $display("======================================================");
        $display("                 TEST SUMMARY");
        $display("======================================================");
        $display("Total PASS = %0d", pass_count);
        $display("Total FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display("*************** ALL TESTS PASSED ***************");
        else
            $display("*************** TESTS FAILED *******************");

        $display("======================================================");

        $finish;

    end

endmodule
