`timescale 1ns/1ps

module multiplier_16bit_tb;

    //============================================================
    // PARAMETERS
    //============================================================
    localparam int DATA_WIDTH = 16;
    localparam int PROD_WIDTH = 2 * DATA_WIDTH;

    //============================================================
    // DUT SIGNALS
    //============================================================
    logic clk;
    logic rst;
    logic start;

    logic [DATA_WIDTH-1:0] A;
    logic [DATA_WIDTH-1:0] B;
    logic signed_mode;

    logic [PROD_WIDTH-1:0] product;
    logic valid_out;
    logic overflow;

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

        input logic [15:0] test_A;
        input logic [15:0] test_B;
        input logic        test_mode;
        input logic [31:0] expected_product;
        input logic        expected_overflow;

        begin

            // Apply inputs before rising edge
            @(negedge clk);

            A           = test_A;
            B           = test_B;
            signed_mode = test_mode;
            start       = 1'b1;

            //====================================================
            // Cycle N: Inputs get registered
            //====================================================
            @(posedge clk);
            #1;

            // Remove start after capture
            @(negedge clk);
            start = 1'b0;

            //====================================================
            // Cycle N+1: Result becomes valid
            //====================================================
            @(posedge clk);
            #1;

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
            16'h000A,
            16'h0014,
            1'b0,
            32'h0000_00C8,
            1'b0
        );

        // 255 * 255 = 65025
        test_case(
            16'h00FF,
            16'h00FF,
            1'b0,
            32'h0000_FE01,
            1'b0
        );

        // 65535 * 1 = 65535
        test_case(
            16'hFFFF,
            16'h0001,
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

        // 65535 * 2 = 131070
        test_case(
            16'hFFFF,
            16'h0002,
            1'b0,
            32'h0001_FFFE,
            1'b1
        );

        // 0 * 65535 = 0
        test_case(
            16'h0000,
            16'hFFFF,
            1'b0,
            32'h0000_0000,
            1'b0
        );

        //========================================================
        // SIGNED NORMAL TESTS
        //========================================================
        $display("");
        $display("----------------- SIGNED TESTS -----------------");

        // 10 * 20 = 200
        test_case(
            16'h000A,
            16'h0014,
            1'b1,
            32'h0000_00C8,
            1'b0
        );

        // -10 * 20 = -200
        test_case(
            16'hFFF6,
            16'h0014,
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
            16'h0001,
            1'b1,
            32'h0000_7FFF,
            1'b0
        );

        // -32768 * 1 = -32768
        test_case(
            16'h8000,
            16'h0001,
            1'b1,
            32'hFFFF_8000,
            1'b0
        );

        // -1 * -1 = 1
        test_case(
            16'hFFFF,
            16'hFFFF,
            1'b1,
            32'h0000_0001,
            1'b0
        );

        // -1 * 2 = -2
        test_case(
            16'hFFFF,
            16'h0002,
            1'b1,
            32'hFFFF_FFFE,
            1'b0
        );

        //========================================================
        // SIGNED OVERFLOW TESTS
        //========================================================
        $display("");
        $display("-------------- SIGNED OVERFLOW ----------------");

        // 20000 * 2 = 40000
        test_case(
            16'h4E20,
            16'h0002,
            1'b1,
            32'h0000_9C40,
            1'b1
        );

        // -20000 * 2 = -40000
        test_case(
            16'hB1E0,
            16'h0002,
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

        // 32767 * 2 = 65534
        test_case(
            16'h7FFF,
            16'h0002,
            1'b1,
            32'h0000_FFFE,
            1'b1
        );

        //========================================================
        // MODE SWITCHING
        //========================================================
        $display("");
        $display("---------------- MODE SWITCHING ----------------");

        // Same bit pattern FFFF:
        // Unsigned = 65535
        test_case(
            16'hFFFF,
            16'h0001,
            1'b0,
            32'h0000_FFFF,
            1'b0
        );

        // Same bit pattern FFFF:
        // Signed = -1
        test_case(
            16'hFFFF,
            16'h0001,
            1'b1,
            32'hFFFF_FFFF,
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
