`timescale 1ns/1ps

module tb_parameterized_adder;

    parameter WIDTH = 16;

    logic [WIDTH-1:0] A;
    logic [WIDTH-1:0] B;
    logic             Cin;
    logic [WIDTH-1:0] Sum;
    logic             Cout;

    parameterized_adder #(.WIDTH(WIDTH)) dut (
        .A(A),
        .B(B),
        .Cin(Cin),
        .Sum(Sum),
        .Cout(Cout)
    );

    task check_result(
        input logic [WIDTH-1:0] test_A,
        input logic [WIDTH-1:0] test_B,
        input logic             test_Cin
    );
        logic [WIDTH:0] expected;

        begin
            A = test_A;
            B = test_B;
            Cin = test_Cin;

            #20;

            expected = test_A + test_B + test_Cin;

            if ({Cout, Sum} == expected)
                $display("PASS: A=%h B=%h Cin=%b -> Cout=%b Sum=%h",
                         A, B, Cin, Cout, Sum);
            else
                $display("FAIL: A=%h B=%h Cin=%b -> Cout=%b Sum=%h, Expected=%h",
                         A, B, Cin, Cout, Sum, expected);
        end
    endtask

    initial begin

        $display("===== Parameterized Adder Test =====");

        // Test 1: Zero
        check_result(16'h0000, 16'h0000, 1'b0);

        // Test 2: Simple addition
        check_result(16'h0005, 16'h0003, 1'b0);

        // Test 3: Addition with Cin
        check_result(16'h0005, 16'h0003, 1'b1);

        // Test 4: Maximum value + 1
        check_result(16'hFFFF, 16'h0001, 1'b0);

        // Test 5: Maximum value + maximum value
        check_result(16'hFFFF, 16'hFFFF, 1'b0);

        // Test 6: Maximum value + maximum value + Cin
        check_result(16'hFFFF, 16'hFFFF, 1'b1);

        // Test 7: Random test
        check_result(16'h1234, 16'h5678, 1'b0);

        // Test 8: Random test with Cin
        check_result(16'hAAAA, 16'h5555, 1'b1);

        // Test 9
        check_result(16'h8000, 16'h8000, 1'b0);

        // Test 10
        check_result(16'h7FFF, 16'h0001, 1'b0);

        $display("===== Test Completed =====");

        $finish;
    end

endmodule
