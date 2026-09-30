`timescale 1ns/1ps

module multiplier16_tb;

    //============================================================
    // SIGNALS
    //============================================================
    logic        clk;
    logic        rst;
    logic [15:0] a;
    logic [15:0] b;
    logic        signed_mode;
    logic        start;

    logic [31:0] product;
    logic        valid;
    logic        overflow;

    //============================================================
    // DUT
    //============================================================
    multiplier16 dut (
        .clk         (clk),
        .rst         (rst),
        .a           (a),
        .b           (b),
        .signed_mode (signed_mode),
        .start       (start),
        .product     (product),
        .valid       (valid),
        .overflow    (overflow)
    );

    //============================================================
    // CLOCK
    //============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //============================================================
    // TEST COUNTERS
    //============================================================
    integer pass_count;
    integer fail_count;

    //============================================================
    // TEST TASK
    //============================================================
    task automatic test_case(
        input [15:0] test_a,
        input [15:0] test_b,
        input        test_mode,
        input [31:0] expected_product,
        input        expected_overflow
    );
    begin

        // Apply inputs
        @(negedge clk);

        a           = test_a;
        b           = test_b;
        signed_mode = test_mode;
        start       = 1'b1;

        // DUT samples start and inputs
        @(posedge clk);

        #1;

        // Check output
        if (valid !== 1'b1) begin

            $display(
                "FAIL: valid not asserted | a=%h b=%h mode=%b",
                test_a,
                test_b,
                test_mode
            );

            fail_count = fail_count + 1;

        end
        else if ((product !== expected_product) ||
                 (overflow !== expected_overflow)) begin

            $display(
                "FAIL: a=%h b=%h mode=%b | Got product=%h overflow=%b | Expected product=%h overflow=%b",
                test_a,
                test_b,
                test_mode,
                product,
                overflow,
                expected_product,
                expected_overflow
            );

            fail_count = fail_count + 1;

        end
        else begin

            $display(
                "PASS: a=%h b=%h mode=%b | product=%h overflow=%b",
                test_a,
                test_b,
                test_mode,
                product,
                overflow
            );

            pass_count = pass_count + 1;

        end

        // Deassert start
        @(negedge clk);
        start = 1'b0;

    end
    endtask

    //============================================================
    // MAIN TEST
    //============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        a           = 16'h0000;
        b           = 16'h0000;
        signed_mode = 1'b0;
        start       = 1'b0;
        rst         = 1'b1;

        $display("");
        $display("================================================");
        $display("   16-BIT SIGNED / UNSIGNED MULTIPLIER TEST");
        $display("================================================");

        //========================================================
        // RESET TEST
        //========================================================
        @(posedge clk);
        #1;

        if ((product === 32'h0000_0000) &&
            (valid === 1'b0) &&
            (overflow === 1'b0)) begin

            $display("PASS: RESET");
            pass_count = pass_count + 1;

        end
        else begin

            $display(
                "FAIL: RESET | product=%h valid=%b overflow=%b",
                product,
                valid,
                overflow
            );

            fail_count = fail_count + 1;

        end

        rst = 1'b0;

        //========================================================
        // UNSIGNED TESTS
        //========================================================
        $display("");
        $display("---------------- UNSIGNED TESTS ----------------");

        // 10 * 20 = 200
        test_case(
            16'd10,
            16'd20,
            1'b0,
            32'h0000_00C8,
            1'b0
        );

        // 65535 * 1 = 65535
        test_case(
            16'hFFFF,
            16'd1,
            1'b0,
            32'h0000_FFFF,
            1'b0
        );

        // 65535 * 65535 = FFFE0001
        // Overflow for 16-bit unsigned result
        test_case(
            16'hFFFF,
            16'hFFFF,
            1'b0,
            32'hFFFE_0001,
            1'b1
        );

        // 0 * 65535 = 0
        test_case(
            16'd0,
            16'hFFFF,
            1'b0,
            32'h0000_0000,
            1'b0
        );

        //========================================================
        // SIGNED TESTS
        //========================================================
        $display("");
        $display("----------------- SIGNED TESTS -----------------");

        // 10 * 20 = 200
        test_case(
            16'd10,
            16'd20,
            1'b1,
            32'h0000_00C8,
            1'b0
        );

        // -10 * 20 = -200
        test_case(
            16'hFFF6,
            16'd20,
            1'b1,
            32'hFFFF_FF38,
            1'b0
        );

        // -10 * -20 = +200
        test_case(
            16'hFFF6,
            16'hFFEC,
            1'b1,
            32'h0000_00C8,
            1'b0
        );

        // 32767 * 1 = 32767
        test_case(
            16'h7FFF,
            16'd1,
            1'b1,
            32'h0000_7FFF,
            1'b0
        );

        // -32768 * 1 = -32768
        test_case(
            16'h8000,
            16'd1,
            1'b1,
            32'hFFFF_8000,
            1'b0
        );

        // -1 * -1 = +1
        test_case(
            16'hFFFF,
            16'hFFFF,
            1'b1,
            32'h0000_0001,
            1'b0
        );

        //========================================================
        // SIGNED OVERFLOW TESTS
        //========================================================
        $display("");
        $display("-------------- SIGNED OVERFLOW ----------------");

        // 20000 * 2 = 40000
        // 40000 > 32767
        test_case(
            16'd20000,
            16'd2,
            1'b1,
            32'h0000_9C40,
            1'b1
        );

        // -20000 * 2 = -40000
        // -40000 < -32768
        test_case(
            16'hB1E0,
            16'd2,
            1'b1,
            32'hFFFF_63C0,
            1'b1
        );

        // -32768 * -1 = +32768
        // Signed overflow
        test_case(
            16'h8000,
            16'hFFFF,
            1'b1,
            32'h0000_8000,
            1'b1
        );

        // -32768 * -32768 = 1073741824
        // Signed overflow
        test_case(
            16'h8000,
            16'h8000,
            1'b1,
            32'h4000_0000,
            1'b1
        );

        //========================================================
        // MODE TOGGLE TEST
        //========================================================
        $display("");
        $display("---------------- MODE TOGGLE ------------------");

        // Unsigned: 65535 * 2 = 131070
        test_case(
            16'hFFFF,
            16'd2,
            1'b0,
            32'h0001_FFFE,
            1'b1
        );

        // Signed: -1 * 2 = -2
        test_case(
            16'hFFFF,
            16'd2,
            1'b1,
            32'hFFFF_FFFE,
            1'b0
        );

        //========================================================
        // SUMMARY
        //========================================================
        $display("");
        $display("================================================");
        $display("                  TEST SUMMARY");
        $display("================================================");

        $display("PASSED = %0d", pass_count);
        $display("FAILED = %0d", fail_count);

        if (fail_count == 0)
            $display("RESULT = ALL TESTS PASSED");
        else
            $display("RESULT = TEST FAILED");

        $display("================================================");

        #20;
        $finish;

    end

endmodule
