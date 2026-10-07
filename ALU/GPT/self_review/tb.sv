`timescale 1ns/1ps

module parameterized_alu_tb;

    parameter int WIDTH = 16;

    //============================================================
    // DUT signals
    //============================================================
    logic             clk;
    logic             reset;

    logic [WIDTH-1:0] A;
    logic [WIDTH-1:0] B;
    logic [3:0]       opcode;

    logic [WIDTH-1:0] result;
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

    //============================================================
    // Test counters
    //============================================================
    integer pass_count = 0;
    integer fail_count = 0;

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
    // 100 MHz clock
    //============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //============================================================
    // Self-checking test task
    //============================================================
    task automatic check_operation;

        input logic [WIDTH-1:0] test_A;
        input logic [WIDTH-1:0] test_B;
        input logic [3:0]       test_opcode;

        input logic [WIDTH-1:0] expected_result;
        input logic             expected_zero;
        input logic             expected_carry;
        input logic             expected_overflow;
        input logic             expected_negative;

        input string            test_name;

        begin

            // Apply inputs on falling edge
            @(negedge clk);

            A      = test_A;
            B      = test_B;
            opcode = test_opcode;

            // Registered DUT output updates on next rising edge
            @(posedge clk);

            // Allow NBA assignments to settle
            #1;

            if ((result   === expected_result)  &&
                (zero     === expected_zero)    &&
                (carry    === expected_carry)   &&
                (overflow === expected_overflow) &&
                (negative === expected_negative)) begin

                $display(
                    "PASS: %-32s A=%h B=%h RESULT=%h",
                    test_name,
                    test_A,
                    test_B,
                    result
                );

                pass_count = pass_count + 1;

            end
            else begin

                $display("");
                $display("FAIL: %s", test_name);

                $display(
                    "      A=%h B=%h OPCODE=%b",
                    test_A,
                    test_B,
                    test_opcode
                );

                $display(
                    "      Expected: RESULT=%h Z=%b C=%b V=%b N=%b",
                    expected_result,
                    expected_zero,
                    expected_carry,
                    expected_overflow,
                    expected_negative
                );

                $display(
                    "      Actual:   RESULT=%h Z=%b C=%b V=%b N=%b",
                    result,
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
    // TEST SEQUENCE
    //============================================================
    initial begin

        //========================================================
        // Initial values
        //========================================================
        clk    = 1'b0;
        reset  = 1'b1;
        A      = '0;
        B      = '0;
        opcode = OP_ADD;

        //========================================================
        // RESET TEST
        //========================================================
        @(posedge clk);
        #1;

        if ((result   === '0) &&
            (zero     === 1'b1) &&
            (carry    === 1'b0) &&
            (overflow === 1'b0) &&
            (negative === 1'b0)) begin

            $display("PASS: Reset test");
            pass_count = pass_count + 1;

        end
        else begin

            $display("FAIL: Reset test");

            $display(
                "      RESULT=%h Z=%b C=%b V=%b N=%b",
                result,
                zero,
                carry,
                overflow,
                negative
            );

            fail_count = fail_count + 1;

        end

        reset = 1'b0;

        $display("");
        $display("============================================================");
        $display("             PARAMETERIZED ALU TESTBENCH");
        $display("             WIDTH = %0d", WIDTH);
        $display("============================================================");
        $display("");

        //========================================================
        // ADD TESTS
        //========================================================

        check_operation(
            16'h0005,
            16'h0003,
            OP_ADD,
            16'h0008,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "ADD normal"
        );

        // FFFF + 0001 = 0000, carry = 1
        check_operation(
            16'hFFFF,
            16'h0001,
            OP_ADD,
            16'h0000,
            1'b1,
            1'b1,
            1'b0,
            1'b0,
            "ADD unsigned carry"
        );

        // 32767 + 1 = -32768
        check_operation(
            16'h7FFF,
            16'h0001,
            OP_ADD,
            16'h8000,
            1'b0,
            1'b0,
            1'b1,
            1'b1,
            "ADD positive overflow"
        );

        // -32768 + (-1) = 32767
        check_operation(
            16'h8000,
            16'hFFFF,
            OP_ADD,
            16'h7FFF,
            1'b0,
            1'b1,
            1'b1,
            1'b0,
            "ADD negative overflow"
        );

        //========================================================
        // SUB TESTS
        //========================================================

        // 8 - 3 = 5
        check_operation(
            16'h0008,
            16'h0003,
            OP_SUB,
            16'h0005,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            "SUB normal"
        );

        // 3 - 8 = FFFB, unsigned borrow
        check_operation(
            16'h0003,
            16'h0008,
            OP_SUB,
            16'hFFFB,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SUB unsigned borrow"
        );

        // Equal values
        check_operation(
            16'h1234,
            16'h1234,
            OP_SUB,
            16'h0000,
            1'b1,
            1'b1,
            1'b0,
            1'b0,
            "SUB equal"
        );

        // 32767 - (-1) = -32768
        check_operation(
            16'h7FFF,
            16'hFFFF,
            OP_SUB,
            16'h8000,
            1'b0,
            1'b0,
            1'b1,
            1'b1,
            "SUB positive overflow"
        );

        // -32768 - 1 = 32767
        check_operation(
            16'h8000,
            16'h0001,
            OP_SUB,
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
        check_operation(
            16'hAAAA,
            16'h5555,
            OP_AND,
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
        check_operation(
            16'hAAAA,
            16'h5555,
            OP_OR,
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
        check_operation(
            16'hAAAA,
            16'h5555,
            OP_XOR,
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
        check_operation(
            16'hAAAA,
            16'h0000,
            OP_NOT,
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

        // 1 << 4 = 10
        check_operation(
            16'h0001,
            16'h0004,
            OP_SLL,
            16'h0010,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLL by 4"
        );

        // 1 << 15 = 8000
        check_operation(
            16'h0001,
            16'h000F,
            OP_SLL,
            16'h8000,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SLL by 15"
        );

        // Shift by WIDTH
        check_operation(
            16'h1234,
            16'h0010,
            OP_SLL,
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

        // 8000 >> 2 = 2000
        check_operation(
            16'h8000,
            16'h0002,
            OP_SRL,
            16'h2000,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SRL by 2"
        );

        // Shift by WIDTH
        check_operation(
            16'hFFFF,
            16'h0010,
            OP_SRL,
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

        // 8000 >>> 2 = E000
        check_operation(
            16'h8000,
            16'h0002,
            OP_SRA,
            16'hE000,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SRA negative"
        );

        // 4000 >>> 2 = 1000
        check_operation(
            16'h4000,
            16'h0002,
            OP_SRA,
            16'h1000,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SRA positive"
        );

        // Negative value >>> WIDTH = FFFF
        check_operation(
            16'h8000,
            16'h0010,
            OP_SRA,
            16'hFFFF,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            "SRA negative by WIDTH"
        );

        // Positive value >>> WIDTH = 0000
        check_operation(
            16'h4000,
            16'h0010,
            OP_SRA,
            16'h0000,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "SRA positive by WIDTH"
        );

        //========================================================
        // SLT TESTS
        //========================================================

        // 5 < 10
        check_operation(
            16'h0005,
            16'h000A,
            OP_SLT,
            16'h0001,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLT 5 < 10"
        );

        // 10 < 5 = false
        check_operation(
            16'h000A,
            16'h0005,
            OP_SLT,
            16'h0000,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            "SLT 10 < 5"
        );

        // -1 < 1
        check_operation(
            16'hFFFF,
            16'h0001,
            OP_SLT,
            16'h0001,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLT -1 < 1"
        );

        // -32768 < 32767
        check_operation(
            16'h8000,
            16'h7FFF,
            OP_SLT,
            16'h0001,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            "SLT MIN < MAX"
        );

        // 32767 < -32768 = false
        check_operation(
            16'h7FFF,
            16'h8000,
            OP_SLT,
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
        check_operation(
            16'h1234,
            16'h5678,
            4'b1111,
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
        $display("============================================================");
        $display("                     TEST SUMMARY");
        $display("============================================================");
        $display("WIDTH       = %0d", WIDTH);
        $display("PASS COUNT  = %0d", pass_count);
        $display("FAIL COUNT  = %0d", fail_count);

        if (fail_count == 0)
            $display("*************** ALL TESTS PASSED ***************");
        else
            $display("*************** TESTS FAILED *******************");

        $display("============================================================");

        $finish;

    end

endmodule
