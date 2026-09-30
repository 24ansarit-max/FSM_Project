`timescale 1ns/1ps

module multiplier_16bit_tb;

    //============================================================
    // DUT SIGNALS
    //============================================================
    logic        clk;
    logic        rst;
    logic        start;

    logic [15:0] A;
    logic [15:0] B;
    logic        signed_mode;

    logic [31:0] product;
    logic        valid_out;
    logic        overflow;

    //============================================================
    // DUT
    //============================================================
    multiplier_16bit dut (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .A           (A),
        .B           (B),
        .signed_mode (signed_mode),
        .product     (product),
        .valid_out   (valid_out),
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
    // COUNTERS
    //============================================================
    integer pass_count;
    integer fail_count;

    //============================================================
    // TEST TASK
    //============================================================
    task automatic test_case;

        input [15:0] test_A;
        input [15:0] test_B;
        input        test_mode;
        input [31:0] expected_product;
        input        expected_overflow;

        begin

            // Apply inputs before rising edge
            @(negedge clk);

            A           = test_A;
            B           = test_B;
            signed_mode = test_mode;
            start       = 1'b1;

            // DUT captures result
            @(posedge clk);
            #1;

            // Check output
            if (valid_out !== 1'b1) begin

                $display(
                    "FAIL: valid_out=0 | A=%h B=%h Mode=%b",
                    test_A,
                    test_B,
                    test_mode
                );

                fail_count = fail_count + 1;

            end
            else if ((product !== expected_product) ||
                     (overflow !== expected_overflow)) begin

                $display(
                    "FAIL: A=%h B=%h Mode=%b | Got Product=%h Overflow=%b | Expected Product=%h Overflow=%b",
                    test_A,
                    test_B,
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
                    "PASS: A=%h B=%h Mode=%b | Product=%h Overflow=%b",
                    test_A,
                    test_B,
                    test_mode,
                    product,
                    overflow
                );

                pass_count = pass_count + 1;

            end

            // Remove start
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

        A           = 16'h0000;
        B           = 16'h0000;
        signed_mode = 1'b0;
        start       = 1'b0;
        rst         = 1'b1;

        $display("");
        $display("================================================");
        $display("     16-BIT SIGNED/UNSIGNED MULTIPLIER TB");
        $display("================================================");

        //========================================================
        // RESET TEST
        //========================================================
        @(posedge clk);
        #1;

        if ((product === 32'h0000_0000) &&
            (valid_out === 1'b0) &&
            (overflow === 1'b0)) begin

            $display("PASS: RESET");
            pass_count = pass_count + 1;

        end
        else begin

            $display("FAIL: RESET");
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

        // 65535 * 65535 = 4294836225
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
        // -10 = FFF6
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
        test_case(
            16'hB1E0,
            16'd2,
            1'b1,
            32'hFFFF_63C0,
            1'b1
        );

        // -32768 * -1 = +32768
        test_case(
            16'h8000,
            16'hFFFF,
            1'b1,
            32'h0000_8000,
            1'b1
        );

        // -32768 * -32768 = 1073741824
        test_case(
            16'h8000,
            16'h8000,
            1'b1,
            32'h4000_0000,
            1'b1
        );

        //========================================================
        // MODE SWITCHING
        //========================================================
        $display("");
        $display("---------------- MODE SWITCHING ----------------");

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
        // FINAL SUMMARY
        //========================================================
        $display("");
        $display("================================================");
        $display("                 TEST SUMMARY");
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
