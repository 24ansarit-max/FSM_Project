`timescale 1ns/1ps

module testbench;

    parameter DATA_WIDTH = 8;
    parameter DEPTH = 16;
    parameter ALMOST_FULL_THRESHOLD = DEPTH - 2;
    parameter ALMOST_EMPTY_THRESHOLD = 2;
    parameter COUNT_WIDTH = $clog2(DEPTH + 1);

    logic clk;
    logic rst;

    logic wr_en;
    logic [DATA_WIDTH-1:0] wr_data;

    logic rd_en;
    logic [DATA_WIDTH-1:0] rd_data;

    logic full;
    logic empty;
    logic almost_full;
    logic almost_empty;

    logic [COUNT_WIDTH-1:0] fifo_count;

    logic overflow_flag;
    logic underflow_flag;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    logic [DATA_WIDTH-1:0] expected_data;

    //============================================================
    // DUT
    //============================================================

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .ALMOST_FULL_THRESHOLD(ALMOST_FULL_THRESHOLD),
        .ALMOST_EMPTY_THRESHOLD(ALMOST_EMPTY_THRESHOLD)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .full(full),
        .empty(empty),
        .almost_full(almost_full),
        .almost_empty(almost_empty),
        .fifo_count(fifo_count),
        .overflow_flag(overflow_flag),
        .underflow_flag(underflow_flag)
    );

    //============================================================
    // CLOCK: 100 MHz
    //============================================================

    initial clk = 1'b0;
    always #5 clk = ~clk;

    //============================================================
    // TEST TASKS
    //============================================================

    task automatic check(
        input logic condition,
        input string test_name
    );
        begin
            if (condition === 1'b1) begin
                $display("PASS: %s", test_name);
                pass_count = pass_count + 1;
            end
            else begin
                $error("FAIL: %s", test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task automatic reset_fifo;
        begin
            @(negedge clk);
            rst = 1'b1;
            wr_en = 1'b0;
            rd_en = 1'b0;
            wr_data = '0;

            @(negedge clk);
            rst = 1'b0;

            #1;
            check(empty == 1'b1, "Reset: empty asserted");
            check(full == 1'b0, "Reset: full deasserted");
            check(fifo_count == 0, "Reset: count is zero");
            check(overflow_flag == 0, "Reset: overflow cleared");
            check(underflow_flag == 0, "Reset: underflow cleared");
        end
    endtask

    task automatic write_item(input logic [DATA_WIDTH-1:0] data);
        begin
            @(negedge clk);
            wr_en = 1'b1;
            wr_data = data;
            rd_en = 1'b0;

            @(negedge clk);
            wr_en = 1'b0;
            wr_data = '0;
            #1;
        end
    endtask

    task automatic read_item(
        input logic [DATA_WIDTH-1:0] expected
    );
        begin
            @(negedge clk);
            rd_en = 1'b1;
            wr_en = 1'b0;

            // Read occurs at the next rising edge.
            @(posedge clk);
            #1;
            check(rd_data === expected, "FIFO data ordering");

            @(negedge clk);
            rd_en = 1'b0;
            #1;
        end
    endtask

    //============================================================
    // MAIN TEST SEQUENCE
    //============================================================

    initial begin
        rst = 1'b0;
        wr_en = 1'b0;
        wr_data = '0;
        rd_en = 1'b0;

        $display("========================================");
        $display(" SYNCHRONOUS FIFO TESTBENCH");
        $display(" DATA_WIDTH = %0d, DEPTH = %0d", DATA_WIDTH, DEPTH);
        $display("========================================");

        // -------------------------------------------------------
        // TEST 1: Reset
        // -------------------------------------------------------
        reset_fifo();

        // -------------------------------------------------------
        // TEST 2: Underflow when empty
        // -------------------------------------------------------
        @(negedge clk);
        rd_en = 1'b1;

        @(posedge clk);
        #1;
        check(underflow_flag == 1'b1,
              "Underflow flag asserted when reading empty FIFO");
        check(fifo_count == 0,
              "Underflow does not decrement count");

        @(negedge clk);
        rd_en = 1'b0;

        // -------------------------------------------------------
        // TEST 3: Write and read FIFO ordering
        // -------------------------------------------------------
        write_item(8'h11);
        write_item(8'h22);
        write_item(8'h33);

        check(fifo_count == 3, "Count after three writes");
        check(empty == 0, "Empty deasserted after writing");
        check(full == 0, "Full deasserted after three writes");

        read_item(8'h11);
        read_item(8'h22);
        read_item(8'h33);

        check(fifo_count == 0, "Count returns to zero");
        check(empty == 1, "Empty asserted after final read");

        // -------------------------------------------------------
        // TEST 4: Almost-empty threshold
        // -------------------------------------------------------
        write_item(8'hA1);
        write_item(8'hA2);

        #1;
        check(almost_empty == 1,
              "Almost-empty asserted at threshold");

        write_item(8'hA3);
        #1;
        check(almost_empty == 0,
              "Almost-empty deasserted above threshold");

        // Drain the FIFO.
        read_item(8'hA1);
        read_item(8'hA2);
        read_item(8'hA3);

        // -------------------------------------------------------
        // TEST 5: Almost-full threshold
        // -------------------------------------------------------
        for (i = 0; i < ALMOST_FULL_THRESHOLD; i = i + 1)
            write_item(i + 1);

        #1;
        check(almost_full == 1,
              "Almost-full asserted at threshold");

        // Clear FIFO.
        while (!empty)
            read_item(rd_data);

        // -------------------------------------------------------
        // TEST 6: Fill FIFO completely
        // -------------------------------------------------------
        for (i = 0; i < DEPTH; i = i + 1)
            write_item(i);

        #1;
        check(full == 1, "Full asserted at capacity");
        check(fifo_count == DEPTH, "Count equals DEPTH");
        check(almost_full == 1, "Almost-full asserted when full");

        // -------------------------------------------------------
        // TEST 7: Overflow attempt
        // -------------------------------------------------------
        @(negedge clk);
        wr_en = 1'b1;
        wr_data = 8'hEE;

        @(posedge clk);
        #1;
        check(overflow_flag == 1'b1,
              "Overflow flag asserted when writing full FIFO");
        check(fifo_count == DEPTH,
              "Overflow does not increase count");

        @(negedge clk);
        wr_en = 1'b0;

        // Verify no corruption: original data remains in order.
        for (i = 0; i < DEPTH; i = i + 1)
            read_item(i);

        check(empty == 1, "FIFO empty after draining");

        // -------------------------------------------------------
        // TEST 8: Simultaneous read/write in mid-fill state
        // -------------------------------------------------------
        write_item(8'h41);
        write_item(8'h42);
        write_item(8'h43);

        @(negedge clk);
        wr_en = 1'b1;
        wr_data = 8'h44;
        rd_en = 1'b1;

        @(posedge clk);
        #1;
        check(rd_data === 8'h41,
              "Simultaneous read/write returns oldest item");
        check(fifo_count == 3,
              "Simultaneous read/write preserves count");

        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;

        read_item(8'h42);
        read_item(8'h43);
        read_item(8'h44);

        check(empty == 1, "FIFO empty after simultaneous test");

        // -------------------------------------------------------
        // TEST 9: Simultaneous read/write when empty
        // -------------------------------------------------------
        @(negedge clk);
        wr_en = 1'b1;
        wr_data = 8'h55;
        rd_en = 1'b1;

        @(posedge clk);
        #1;
        check(underflow_flag == 1'b1,
              "Empty simultaneous operation reports underflow");
        check(fifo_count == 1,
              "Write accepted while read blocked at empty");

        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;

        read_item(8'h55);

        // -------------------------------------------------------
        // TEST 10: Pointer wrap-around
        // -------------------------------------------------------
        for (i = 0; i < DEPTH; i = i + 1)
            write_item(i + 8'h60);

        for (i = 0; i < DEPTH/2; i = i + 1)
            read_item(i + 8'h60);

        for (i = 0; i < DEPTH/2; i = i + 1)
            write_item(i + 8'h80);

        for (i = DEPTH/2; i < DEPTH; i = i + 1)
            read_item(i + 8'h60);

        for (i = 0; i < DEPTH/2; i = i + 1)
            read_item(i + 8'h80);

        check(empty == 1, "Pointer wrap-around preserves FIFO order");
        check(fifo_count == 0, "Count correct after wrap-around");

        // -------------------------------------------------------
        // SUMMARY
        // -------------------------------------------------------
        $display("========================================");
        $display(" TESTS PASSED: %0d", pass_count);
        $display(" TESTS FAILED: %0d", fail_count);
        $display("========================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // -----------------------------------------------------------
    // Global timeout
    // -----------------------------------------------------------
    initial begin
        #200000;
        $fatal(1, "Global simulation timeout");
    end

endmodule
