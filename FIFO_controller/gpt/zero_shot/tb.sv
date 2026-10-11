
`timescale 1ns/1ps

module testbench;

    parameter DATA_WIDTH = 8;
    parameter DEPTH = 16;
    parameter ALMOST_FULL_THRESHOLD = DEPTH - 2;
    parameter ALMOST_EMPTY_THRESHOLD = 2;

    logic clk, rst;
    logic wr_en, rd_en;
    logic [DATA_WIDTH-1:0] wr_data, rd_data;

    logic full, empty, almost_full, almost_empty;
    logic [$clog2(DEPTH+1)-1:0] fifo_count;
    logic overflow_flag, underflow_flag;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    // Reference FIFO scoreboard
    logic [DATA_WIDTH-1:0] expected_mem [0:DEPTH-1];
    integer head = 0;
    integer tail = 0;
    integer model_count = 0;

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

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    task automatic check(
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

    task automatic check_flags;
        begin
            #1;
            check(fifo_count == model_count,
                  "FIFO count");
            check(full == (model_count == DEPTH),
                  "FULL flag");
            check(empty == (model_count == 0),
                  "EMPTY flag");
            check(almost_full ==
                  (model_count >= ALMOST_FULL_THRESHOLD),
                  "ALMOST_FULL flag");
            check(almost_empty ==
                  (model_count <= ALMOST_EMPTY_THRESHOLD),
                  "ALMOST_EMPTY flag");
        end
    endtask

    task automatic write_item(input logic [DATA_WIDTH-1:0] data);
        begin
            @(negedge clk);
            wr_en = 1;
            wr_data = data;
            rd_en = 0;

            // Save the value accepted by the FIFO.
            if (model_count < DEPTH) begin
                expected_mem[tail] = data;
                tail = (tail + 1) % DEPTH;
                model_count = model_count + 1;
            end

            @(posedge clk);
            #1;
            check(overflow_flag == 0,
                  "No overflow during valid write");

            @(negedge clk);
            wr_en = 0;
            wr_data = 0;

            check_flags();
        end
    endtask

    task automatic read_item;
        logic [DATA_WIDTH-1:0] expected;
        integer had_data;
        begin
            @(negedge clk);
            wr_en = 0;
            rd_en = 1;

            had_data = (model_count > 0);

            if (had_data)
                expected = expected_mem[head];

            @(posedge clk);
            #1;

            if (had_data) begin
                check(rd_data === expected,
                      $sformatf("Read expected=%02h, got=%02h",
                                expected, rd_data));

                head = (head + 1) % DEPTH;
                model_count = model_count - 1;

                check(underflow_flag == 0,
                      "No underflow during valid read");
            end
            else begin
                check(underflow_flag == 1,
                      "Underflow detected");
            end

            @(negedge clk);
            rd_en = 0;

            check_flags();
        end
    endtask

    initial begin
        rst = 1;
        wr_en = 0;
        rd_en = 0;
        wr_data = 0;

        $display("\n========== SYNCHRONOUS FIFO TEST ==========");

        // 1. Reset
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;

        check_flags();
        check(rd_data == 0, "Read data reset to zero");
        check(overflow_flag == 0, "Overflow flag reset");
        check(underflow_flag == 0, "Underflow flag reset");

        // 2. Underflow
        @(negedge clk);
        rd_en = 1;
        @(posedge clk);
        #1;
        check(underflow_flag == 1, "Underflow on empty FIFO");
        @(negedge clk);
        rd_en = 0;
        check_flags();

        // 3. Fill FIFO
        $display("\n--- Fill FIFO ---");
        for (i = 0; i < DEPTH; i = i + 1)
            write_item(8'h20 + i);

        check(full == 1, "FIFO reaches full state");
        check(fifo_count == DEPTH, "Count equals DEPTH");

        // 4. Overflow
        @(negedge clk);
        wr_en = 1;
        wr_data = 8'hEE;
        @(posedge clk);
        #1;
        check(overflow_flag == 1, "Overflow on full FIFO");
        @(negedge clk);
        wr_en = 0;
        wr_data = 0;
        check_flags();

        // 5. Read everything in FIFO order
        $display("\n--- Drain FIFO ---");
        for (i = 0; i < DEPTH; i = i + 1)
            read_item();

        check(empty == 1, "FIFO becomes empty");
        check(fifo_count == 0, "Count returns to zero");

        // 6. Almost-full and almost-empty thresholds
        $display("\n--- Threshold checks ---");
        for (i = 0; i < ALMOST_FULL_THRESHOLD; i = i + 1)
            write_item(8'h50 + i);

        check(almost_full == 1, "Almost-full threshold reached");

        while (model_count > ALMOST_EMPTY_THRESHOLD)
            read_item();

        check(almost_empty == 1, "Almost-empty threshold reached");

        while (model_count > 0)
            read_item();

        // 7. Simultaneous read/write while nonempty
        $display("\n--- Simultaneous read/write ---");
        write_item(8'hA1);
        write_item(8'hA2);

        @(negedge clk);
        wr_en = 1;
        wr_data = 8'hA3;
        rd_en = 1;

        // The oldest entry should be read while A3 is written.
        @(posedge clk);
        #1;
        check(rd_data === 8'hA1,
              "Simultaneous read returns oldest entry");

        head = (head + 1) % DEPTH;
        model_count = model_count - 1;

        expected_mem[tail] = 8'hA3;
        tail = (tail + 1) % DEPTH;
        model_count = model_count + 1;

        @(negedge clk);
        wr_en = 0;
        rd_en = 0;
        wr_data = 0;
        check_flags();

        read_item();
        read_item();

        // 8. Pointer wraparound
        $display("\n--- Pointer wraparound ---");
        for (i = 0; i < DEPTH; i = i + 1)
            write_item(8'h60 + i);

        for (i = 0; i < DEPTH/2; i = i + 1)
            read_item();

        for (i = 0; i < DEPTH/2; i = i + 1)
            write_item(8'h90 + i);

        while (model_count > 0)
            read_item();

        check(empty == 1, "Empty after pointer wraparound");
        check(fifo_count == 0, "Count zero after wraparound");

        // 9. Summary
        $display("\n==========================================");
        $display("PASS COUNT = %0d", pass_count);
        $display("FAIL COUNT = %0d", fail_count);
        $display("==========================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED: CHECK ERROR MESSAGES");

        $finish;
    end

    // Timeout
    initial begin
        #200000;
        $fatal(1, "TIMEOUT");
    end

endmodule
