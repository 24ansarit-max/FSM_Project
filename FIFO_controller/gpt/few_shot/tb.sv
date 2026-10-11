
`timescale 1ns/1ps

module testbench;

    parameter DATA_WIDTH = 8;
    parameter DEPTH = 16;
    parameter ALMOST_FULL_THRESHOLD = DEPTH - 1;
    parameter ALMOST_EMPTY_THRESHOLD = 1;

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

    logic [$clog2(DEPTH):0] fifo_count;

    logic overflow_flag;
    logic underflow_flag;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    logic [DATA_WIDTH-1:0] expected_mem [0:DEPTH-1];
    integer head;
    integer tail;
    integer model_count;

    // DUT
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

    // 100 MHz clock: 10 ns period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Scoreboard model
    task automatic model_write(input logic [DATA_WIDTH-1:0] data);
        begin
            expected_mem[tail] = data;
            tail = (tail + 1) % DEPTH;
            model_count = model_count + 1;
        end
    endtask

    task automatic model_read;
        begin
            head = (head + 1) % DEPTH;
            model_count = model_count - 1;
        end
    endtask

    task automatic check_condition(
        input logic condition,
        input string message
    );
        begin
            if (condition === 1'b1) begin
                pass_count = pass_count + 1;
                $display("[PASS] %s", message);
            end
            else begin
                fail_count = fail_count + 1;
                $error("[FAIL] %s", message);
            end
        end
    endtask

    task automatic check_status;
        begin
            #1;
            check_condition(fifo_count == model_count,
                            "FIFO count matches scoreboard");
            check_condition(full == (model_count == DEPTH),
                            "FULL flag");
            check_condition(empty == (model_count == 0),
                            "EMPTY flag");
            check_condition(
                almost_full == (model_count >= ALMOST_FULL_THRESHOLD),
                "ALMOST_FULL flag"
            );
            check_condition(
                almost_empty == (model_count <= ALMOST_EMPTY_THRESHOLD),
                "ALMOST_EMPTY flag"
            );
        end
    endtask

    // Write one item and update the reference model
    task automatic write_item(input logic [DATA_WIDTH-1:0] data);
        begin
            @(negedge clk);
            wr_en = 1'b1;
            wr_data = data;
            rd_en = 1'b0;

            @(posedge clk);
            if (!full) begin
                model_write(data);
            end

            @(negedge clk);
            wr_en = 1'b0;
            wr_data = '0;

            check_status();
        end
    endtask

    // Read one item and compare against the reference model
    task automatic read_item;
        logic [DATA_WIDTH-1:0] expected;
        begin
            @(negedge clk);
            wr_en = 1'b0;
            rd_en = 1'b1;

            if (model_count > 0)
                expected = expected_mem[head];
            else
                expected = '0;

            @(posedge clk);
            if (model_count > 0) begin
                #1;
                check_condition(rd_data === expected,
                                $sformatf("Read data expected=%0h actual=%0h",
                                          expected, rd_data));
                model_read();
            end
            else begin
                check_condition(underflow_flag === 1'b1,
                                "Underflow flag asserted");
            end

            @(negedge clk);
            rd_en = 1'b0;

            check_status();
        end
    endtask

    // Main tests
    initial begin
        rst = 1'b1;
        wr_en = 1'b0;
        wr_data = '0;
        rd_en = 1'b0;

        head = 0;
        tail = 0;
        model_count = 0;

        $display("\n======================================");
        $display("       SYNCHRONOUS FIFO TEST");
        $display("======================================");

        // Reset
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        check_status();

        check_condition(rd_data == 0, "Read data reset to zero");
        check_condition(overflow_flag == 0, "Overflow flag reset");
        check_condition(underflow_flag == 0, "Underflow flag reset");

        // Test underflow on empty FIFO
        @(negedge clk);
        rd_en = 1'b1;
        @(posedge clk);
        #1;
        check_condition(underflow_flag == 1'b1,
                        "Underflow detected on empty FIFO");
        @(negedge clk);
        rd_en = 1'b0;
        check_status();

        // Fill FIFO
        $display("\n--- Fill FIFO ---");
        for (i = 0; i < DEPTH; i = i + 1)
            write_item(8'h10 + i);

        check_condition(full == 1'b1, "FIFO becomes full");
        check_condition(fifo_count == DEPTH, "Count equals DEPTH");

        // Overflow attempt
        @(negedge clk);
        wr_en = 1'b1;
        wr_data = 8'hEE;
        @(posedge clk);
        #1;
        check_condition(overflow_flag == 1'b1,
                        "Overflow detected when FIFO is full");
        @(negedge clk);
        wr_en = 1'b0;
        wr_data = '0;
        check_status();

        // Drain FIFO and verify ordering
        $display("\n--- Drain FIFO ---");
        for (i = 0; i < DEPTH; i = i + 1)
            read_item();

        check_condition(empty == 1'b1, "FIFO becomes empty");
        check_condition(fifo_count == 0, "Count returns to zero");

        // Simultaneous read/write while FIFO contains data
        $display("\n--- Simultaneous read/write ---");
        write_item(8'hA1);
        write_item(8'hA2);

        @(negedge clk);
        wr_en = 1'b1;
        wr_data = 8'hA3;
        rd_en = 1'b1;

        // Expected oldest item is A1
        @(posedge clk);
        #1;
        check_condition(rd_data === 8'hA1,
                        "Simultaneous operation returns oldest data");

        model_read();
        model_write(8'hA3);

        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;
        check_status();

        read_item();
        read_item();

        // Pointer wraparound test
        $display("\n--- Pointer wraparound ---");
        for (i = 0; i < DEPTH; i = i + 1)
            write_item(i + 8'h40);

        for (i = 0; i < DEPTH/2; i = i + 1)
            read_item();

        for (i = 0; i < DEPTH/2; i = i + 1)
            write_item(i + 8'h80);

        while (model_count > 0)
            read_item();

        check_condition(empty == 1'b1,
                        "FIFO empty after wraparound test");
        check_condition(fifo_count == 0,
                        "Count zero after wraparound test");

        // Final result
        $display("\n======================================");
        $display("PASS COUNT = %0d", pass_count);
        $display("FAIL COUNT = %0d", fail_count);
        $display("======================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // Timeout protection
    initial begin
        #200000;
        $fatal(1, "TIMEOUT: Testbench did not finish");
    end

endmodule
