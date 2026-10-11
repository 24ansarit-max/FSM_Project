
`timescale 1ns/1ps

module testbench;

    parameter DATA_WIDTH = 8;
    parameter CLK_DIV = 4;

    logic clk, rst, start, miso;
    logic [DATA_WIDTH-1:0] tx_data;

    wire sclk, mosi, cs_n;
    wire [DATA_WIDTH-1:0] rx_data;
    wire busy, done;

    integer errors;
    integer tests;
    integer i;
    logic [7:0] slave_data;
    logic [7:0] received_data;

    // DUT
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

    // System clock: 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // SPI slave: Mode 0
    // Set MISO before each rising SCLK edge.
    always @(negedge sclk) begin
        if (!cs_n && i < DATA_WIDTH) begin
            miso = slave_data[7-i];
            i = i + 1;
        end
    end

    task automatic transfer(
        input logic [7:0] master_data,
        input logic [7:0] slave_response
    );
        integer timeout;
        integer bit_no;
        logic [7:0] observed_tx;
        begin
            tests = tests + 1;

            @(negedge clk);
            tx_data = master_data;
            slave_data = slave_response;
            miso = slave_response[7];
            i = 1;
            start = 1;

            @(negedge clk);
            start = 0;

            observed_tx = 0;

            // Check transmitted MOSI on rising SCLK edges
            bit_no = 0;
            timeout = 0;

            while (done !== 1'b1 && timeout < 1000) begin
                @(posedge sclk);
                if (!cs_n && bit_no < 8) begin
                    observed_tx[7-bit_no] = mosi;
                    bit_no = bit_no + 1;
                end
                timeout = timeout + 1;
            end

            // Wait for completion, with a bounded timeout
            while (done !== 1'b1 && timeout < 1200) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            // Allow registered outputs to settle
            @(negedge clk);

            if (timeout >= 1200) begin
                $display("FAIL: Timeout for TX=%02h", master_data);
                errors = errors + 1;
            end
            else begin
                if (observed_tx === master_data)
                    $display("PASS: MOSI TX=%02h", observed_tx);
                else begin
                    $display("FAIL: MOSI expected=%02h got=%02h",
                             master_data, observed_tx);
                    errors = errors + 1;
                end

                if (rx_data === slave_response)
                    $display("PASS: MISO RX=%02h", rx_data);
                else begin
                    $display("FAIL: RX expected=%02h got=%02h",
                             slave_response, rx_data);
                    errors = errors + 1;
                end

                if (cs_n !== 1'b1 || busy !== 1'b0) begin
                    $display("FAIL: CS/BUSY incorrect after transfer");
                    errors = errors + 1;
                end
            end

            repeat (3) @(negedge clk);
        end
    endtask

    initial begin
        rst = 1;
        start = 0;
        tx_data = 0;
        miso = 0;
        slave_data = 0;
        i = 0;
        errors = 0;
        tests = 0;

        $display("==================================");
        $display(" SPI MASTER TESTBENCH - MODE 0");
        $display("==================================");

        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        if (cs_n === 1'b1 && sclk === 1'b0 &&
            busy === 1'b0 && rx_data === 8'h00)
            $display("PASS: Reset");
        else begin
            $display("FAIL: Reset");
            errors = errors + 1;
        end

        transfer(8'hA5, 8'h3C);
        transfer(8'h96, 8'h69);
        transfer(8'hFF, 8'h00);
        transfer(8'h00, 8'hFF);

        $display("----------------------------------");
        $display("Transfers: %0d", tests);
        $display("Errors:    %0d", errors);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");

        $display("==================================");
        $finish;
    end

    initial begin
        #200000;
        $display("FATAL: Global simulation timeout");
        $finish;
    end

endmodule
