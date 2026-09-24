`timescale 1ns/1ps

module tb_parameterized_adder;

    //====================================================
    // Parameters
    //====================================================

    localparam int WIDTH = 16;


    //====================================================
    // Signals
    //====================================================

    logic [WIDTH-1:0] a;
    logic [WIDTH-1:0] b;
    logic             cin;

    logic [WIDTH-1:0] sum;
    logic             cout;
    logic             overflow;


    //====================================================
    // DUT
    //====================================================

    parameterized_adder #(
        .WIDTH(WIDTH)
    ) dut (
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum),
        .cout(cout),
        .overflow(overflow)
    );


    //====================================================
    // Expected values
    //====================================================

    logic [WIDTH:0] expected_result;
    logic expected_overflow;


    //====================================================
    // CHECK TASK
    //====================================================

    task check_adder;

        input logic [WIDTH-1:0] test_a;
        input logic [WIDTH-1:0] test_b;
        input logic             test_cin;

        begin

            a   = test_a;
            b   = test_b;
            cin = test_cin;

            #1;

            // Expected unsigned result
            expected_result = {1'b0, test_a} +
                              {1'b0, test_b} +
                              test_cin;

            // Expected signed overflow
            expected_overflow =
                ~(test_a[WIDTH-1] ^ test_b[WIDTH-1]) &
                (expected_result[WIDTH-1] ^ test_a[WIDTH-1]);


            if ((sum == expected_result[WIDTH-1:0]) &&
                (cout == expected_result[WIDTH]) &&
                (overflow == expected_overflow)) begin

                $display(
                    "PASS: A=%h B=%h Cin=%b | Cout=%b Sum=%h Overflow=%b",
                    a, b, cin, cout, sum, overflow
                );

            end
            else begin

                $display(
                    "FAIL: A=%h B=%h Cin=%b | Expected: Cout=%b Sum=%h Overflow=%b | Got: Cout=%b Sum=%h Overflow=%b",
                    a, b, cin,
                    expected_result[WIDTH],
                    expected_result[WIDTH-1:0],
                    expected_overflow,
                    cout,
                    sum,
                    overflow
                );

            end

        end

    endtask


    //====================================================
    // TEST SEQUENCE
    //====================================================

    initial begin

        $display("");
        $display("==============================================");
        $display("     PARAMETERIZED ADDER TESTBENCH");
        $display("==============================================");


        //================================================
        // TEST 1 : ZERO
        //================================================

        $display("");
        $display("TEST 1 : ZERO");

        check_adder(
            16'h0000,
            16'h0000,
            1'b0
        );


        //================================================
        // TEST 2 : NORMAL ADDITION
        //================================================

        $display("");
        $display("TEST 2 : NORMAL ADDITION");

        check_adder(
            16'h0005,
            16'h0003,
            1'b0
        );


        //================================================
        // TEST 3 : ADDITION WITH CIN
        //================================================

        $display("");
        $display("TEST 3 : ADDITION WITH CIN");

        check_adder(
            16'h0005,
            16'h0003,
            1'b1
        );


        //================================================
        // TEST 4 : CARRY OUT
        //================================================

        $display("");
        $display("TEST 4 : CARRY OUT");

        check_adder(
            16'hFFFF,
            16'h0001,
            1'b0
        );


        //================================================
        // TEST 5 : MAX + MAX
        //================================================

        $display("");
        $display("TEST 5 : MAX + MAX");

        check_adder(
            16'hFFFF,
            16'hFFFF,
            1'b0
        );


        //================================================
        // TEST 6 : MAX + MAX + CIN
        //================================================

        $display("");
        $display("TEST 6 : MAX + MAX + CIN");

        check_adder(
            16'hFFFF,
            16'hFFFF,
            1'b1
        );


        //================================================
        // TEST 7 : SIGNED POSITIVE OVERFLOW
        // 32767 + 1 = -32768
        //================================================

        $display("");
        $display("TEST 7 : SIGNED POSITIVE OVERFLOW");

        check_adder(
            16'h7FFF,
            16'h0001,
            1'b0
        );


        //================================================
        // TEST 8 : SIGNED NEGATIVE OVERFLOW
        // -32768 + (-1) = 32767
        //================================================

        $display("");
        $display("TEST 8 : SIGNED NEGATIVE OVERFLOW");

        check_adder(
            16'h8000,
            16'hFFFF,
            1'b0
        );


        //================================================
        // TEST 9 : NO SIGNED OVERFLOW
        // -1 + -1 = -2
        //================================================

        $display("");
        $display("TEST 9 : NEGATIVE ADDITION");

        check_adder(
            16'hFFFF,
            16'hFFFF,
            1'b0
        );


        //================================================
        // TEST 10 : RANDOM TESTS
        //================================================

        $display("");
        $display("TEST 10 : RANDOM TESTS");

        repeat (10) begin

            check_adder(
                $urandom,
                $urandom,
                $urandom_range(0,1)
            );

        end


        //================================================
        // END
        //================================================

        $display("");
        $display("==============================================");
        $display("       SIMULATION COMPLETED");
        $display("==============================================");

        #10;

        $finish;

    end

endmodule
