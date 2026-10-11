
`timescale 1ns/1ps

module testbench;

    parameter DATA_WIDTH = 8;
    parameter CLK_DIV    = 4;

    logic clk;
    logic rst;
    logic start;
    logic [DATA_WIDTH-1:0] tx_data;
    logic miso;

    wire sclk;
    wire mosi;
    wire cs_n;
    wire [DATA_WIDTH-1:0] rx_data;
    wire busy;
    wire done;

    logic [DATA_WIDTH-1:0] slave_data;
    integer rx_index;
    integer errors;
    integer tests;

    // DUT: SPI Master, Mode 0
    spi_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .CLK_DIV(CLK_DIV),
        .CPOL(1'b0),
        .CPHA(1'b0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .tx_data(tx_data),
        .miso(miso),
        .sclk(sclk),
        .mosi(mosi),
        .cs_n(cs_n),
        .rx_data(rx_data),
        .busy(busy),
        .done(done)
    );

    // 100 MHz system clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // SPI slave model: Mode 0.
    // MISO changes on falling SCLK edges.
    always @(negedge sclk) begin
        if (!cs_n && rx_index > 0) begin
            rx_index = rx_index - 1;
            miso = slave_data[rx_index];
        end
    end

    // Test task
    task automatic run_transfer(
        input logic [7:0] master_tx,
        input logic [7:0] slave_tx
    );
        integer timeout_count;
        begin
            tests = tests + 1;

            @(negedge clk);
            tx_data   = master_tx;
            slave_data = slave_tx;
            miso      = slave_tx[7];
            rx_index  = 7;
            start     = 1'b1;

            @(negedge clk);
            start = 1'b0;

            timeout_count = 0;

            while (done !== 1'b1 && timeout_count < 2000) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end

            if (timeout_count >= 2000) begin
                $display("FAIL: Timeout for TX=%02h", master_tx);
                errors = errors + 1;
            end
            else begin
                if (rx_data === slave_tx) begin
                    $display(
                        "PASS: TX=%02h RX=%02h",
                        master_tx, rx_data
                    );
                end
                else begin
                    $display(
                        "FAIL: TX=%02h Expected RX=%02h Got RX=%02h",
                        master_tx, slave_tx, rx_data
                    );
                    errors = errors + 1;
                end

                if (cs_n !== 1'b1) begin
                    $display("FAIL: CS not inactive after transfer");
                    errors = errors + 1;
                end

                if (busy !== 1'b0) begin
                    $display("FAIL: BUSY still high after transfer");
                    errors = errors + 1;
                end

                if (sclk !== 1'b0) begin
                    $display("FAIL: SCLK not at CPOL idle level");
                    errors = errors + 1;
                end
            end

            // Allow DUT to return to IDLE
            repeat (3) @(negedge clk);
        end
    endtask

    // Main test sequence
    initial begin
        rst        = 1'b1;
        start      = 1'b0;
        tx_data    = '0;
        miso       = 1'b0;
        slave_data = '0;
        rx_index   = 0;
        errors     = 0;
        tests      = 0;

        $display("======================================");
        $display("     SPI MASTER TESTBENCH - MODE 0");
        $display("======================================");

        // Reset test
        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        if (cs_n === 1'b1 &&
            sclk === 1'b0 &&
            busy === 1'b0 &&
            rx_data === 8'h00) begin
            $display("PASS: Reset and idle outputs");
        end
        else begin
            $display("FAIL: Reset and idle outputs");
            errors = errors + 1;
        end

        // SPI data transfer tests
        run_transfer(8'hA5, 8'h3C);
        run_transfer(8'h96, 8'h69);
        run_transfer(8'hFF, 8'h00);
        run_transfer(8'h00, 8'hFF);

        $display("--------------------------------------");
        $display("Tests executed: %0d", tests);
        $display("Errors:         %0d", errors);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $display("======================================");
        $finish;
    end

endmodule
