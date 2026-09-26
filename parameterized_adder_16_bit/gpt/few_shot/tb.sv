module tb_parameterized_adder;

    parameter WIDTH = 16;

    logic [WIDTH-1:0] a;
    logic [WIDTH-1:0] b;
    logic             cin;

    logic [WIDTH-1:0] sum;
    logic             cout;
    logic             overflow;

    int test_count;
    int error_count;

    logic [WIDTH:0] expected_result;
    logic [WIDTH-1:0] expected_sum;
    logic expected_cout;
    logic expected_overflow;


    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------

    parameterized_adder #(
        .WIDTH(WIDTH)
    ) dut (
        .a        (a),
        .b        (b),
        .cin      (cin),
        .sum      (sum),
        .cout      (cout),
        .overflow (overflow)
    );


    // --------------------------------------------------------
    // Reference model
    // --------------------------------------------------------

    task automatic check_result(
        input logic [WIDTH-1:0] test_a,
        input logic [WIDTH-1:0] test_b,
        input logic             test_cin
    );

        begin

            a   = test_a;
            b   = test_b;
            cin = test_cin;

            #1;

            // Expected WIDTH+1 bit unsigned result
            expected_result =
                {1'b0, test_a} +
                {1'b0, test_b} +
                test_cin;

            expected_sum  = expected_result[WIDTH-1:0];
            expected_cout = expected_result[WIDTH];

            // Signed overflow reference model
            expected_overflow =
                ~(test_a[WIDTH-1] ^ test_b[WIDTH-1]) &
                 (expected_sum[WIDTH-1] ^ test_a[WIDTH-1]);

            test_count++;

            if ((sum !== expected_sum) ||
                (cout !== expected_cout) ||
                (overflow !== expected_overflow)) begin

                error_count++;

                $display("ERROR");
                $display("A             = %h", test_a);
                $display("B             = %h", test_b);
                $display("Cin           = %b", test_cin);
                $display("Expected Sum  = %h", expected_sum);
                $display("Actual Sum    = %h", sum);
                $display("Expected Cout = %b", expected_cout);
                $display("Actual Cout   = %b", cout);
                $display("Expected OVF  = %b", expected_overflow);
                $display("Actual OVF    = %b", overflow);
                $display("--------------------------------------");

            end
            else begin

                $display(
                    "PASS: A=%h B=%h Cin=%b -> Sum=%h Cout=%b Overflow=%b",
                    test_a,
                    test_b,
                    test_cin,
                    sum,
                    cout,
                    overflow
                );

            end

        end

    endtask


    // --------------------------------------------------------
    // Test sequence
    // --------------------------------------------------------

    initial begin

        test_count = 0;
        error_count = 0;

        a   = '0;
        b   = '0;
        cin = 1'b0;

        #10;

        $display("");
        $display("==========================================");
        $display(" PARAMETERIZED ADDER TESTBENCH");
        $display(" WIDTH = %0d", WIDTH);
        $display("==========================================");
        $display("");


        // ----------------------------------------------------
        // Test 1: Zero + Zero
        // ----------------------------------------------------

        check_result(
            '0,
            '0,
            1'b0
        );


        // ----------------------------------------------------
        // Test 2: Simple addition
        // ----------------------------------------------------

        check_result(
            16'h0005,
            16'h0003,
            1'b0
        );


        // ----------------------------------------------------
        // Test 3: Addition with carry-in
        // ----------------------------------------------------

        check_result(
            16'h0005,
            16'h0003,
            1'b1
        );


        // ----------------------------------------------------
        // Test 4: Maximum value + 1
        // ----------------------------------------------------

        check_result(
            {WIDTH{1'b1}},
            {{(WIDTH-1){1'b0}}, 1'b1},
            1'b0
        );


        // ----------------------------------------------------
        // Test 5: Maximum + Maximum
        // ----------------------------------------------------

        check_result(
            {WIDTH{1'b1}},
            {WIDTH{1'b1}},
            1'b0
        );


        // ----------------------------------------------------
        // Test 6: Maximum + Maximum + Carry-in
        // ----------------------------------------------------

        check_result(
            {WIDTH{1'b1}},
            {WIDTH{1'b1}},
            1'b1
        );


        // ----------------------------------------------------
        // Test 7: Zero + Carry-in
        // ----------------------------------------------------

        check_result(
            '0,
            '0,
            1'b1
        );


        // ----------------------------------------------------
        // Test 8: Signed positive overflow
        //
        // 0111...1111 + 1
        // = 1000...0000
        // ----------------------------------------------------

        check_result(
            {1'b0, {(WIDTH-1){1'b1}}},
            {{(WIDTH-1){1'b0}}, 1'b1},
            1'b0
        );


        // ----------------------------------------------------
        // Test 9: Signed negative overflow
        //
        // 1000...0000 + 1111...1111
        // ----------------------------------------------------

        check_result(
            {1'b1, {(WIDTH-1){1'b0}}},
            {WIDTH{1'b1}},
            1'b0
        );


        // ----------------------------------------------------
        // Test 10: Positive + Positive without overflow
        // ----------------------------------------------------

        check_result(
            16'h1000,
            16'h2000,
            1'b0
        );


        // ----------------------------------------------------
        // Test 11: Negative + Negative without overflow
        // ----------------------------------------------------

        check_result(
            16'hF000,
            16'hE000,
            1'b0
        );


        // ----------------------------------------------------
        // Test 12: Positive + Negative
        // ----------------------------------------------------

        check_result(
            16'h0005,
            16'hFFFD,
            1'b0
        );


        // ----------------------------------------------------
        // Random testing
        // ----------------------------------------------------

        repeat (1000) begin

            check_result(
                $urandom,
                $urandom,
                $urandom_range(0,1)
            );

        end


        // ----------------------------------------------------
        // Final result
        // ----------------------------------------------------

        $display("");
        $display("==========================================");
        $display(" TEST SUMMARY");
        $display("==========================================");
        $display("Total Tests : %0d", test_count);
        $display("Errors      : %0d", error_count);

        if (error_count == 0) begin
            $display("");
            $display("ALL TESTS PASSED");
            $display("");
        end
        else begin
            $display("");
            $display("TEST FAILED");
            $display("");
        end

        $display("==========================================");

        $finish;

    end

endmodule
