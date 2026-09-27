`timescale 1ns/1ps

module testbench;

    parameter WIDTH = 8;

    logic clk;
    logic rst;

    logic coin_valid;
    logic [WIDTH-1:0] coin_value;

    logic item_select;
    logic [WIDTH-1:0] item_price;
    logic stock_available;

    logic dispense;
    logic [WIDTH-1:0] change_amount;
    logic error;

    //==========================================================
    // DUT
    //==========================================================
    vending_machine #(
        .WIDTH(WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .coin_valid(coin_valid),
        .coin_value(coin_value),
        .item_select(item_select),
        .item_price(item_price),
        .stock_available(stock_available),
        .dispense(dispense),
        .change_amount(change_amount),
        .error(error)
    );

    //==========================================================
    // Clock
    //==========================================================
    always #5 clk = ~clk;

    //==========================================================
    // Insert coin task
    //==========================================================
    task insert_coin(input [WIDTH-1:0] value);
    begin
        @(negedge clk);
        coin_value = value;
        coin_valid = 1'b1;

        @(negedge clk);
        coin_valid = 1'b0;
        coin_value = '0;
    end
    endtask

    //==========================================================
    // Select item task
    //==========================================================
    task select_item;
    begin
        @(negedge clk);
        item_select = 1'b1;

        @(negedge clk);
        item_select = 1'b0;
    end
    endtask

    //==========================================================
    // TESTS
    //==========================================================
    initial begin

        // Initial values
        clk             = 1'b0;
        rst             = 1'b1;
        coin_valid      = 1'b0;
        coin_value      = '0;
        item_select     = 1'b0;
        item_price      = '0;
        stock_available = 1'b0;

        // Reset
        repeat (2) @(posedge clk);
        rst = 1'b0;

        //======================================================
        // TEST 1: Exact payment
        // Price = 7
        // Coins = 5 + 2
        // Expected: dispense = 1, change = 0
        //======================================================

        $display("");
        $display("========================================");
        $display("TEST 1: EXACT PAYMENT");
        $display("========================================");

        item_price      = 8'd7;
        stock_available = 1'b1;

        insert_coin(8'd5);
        insert_coin(8'd2);

        select_item();

        // Wait for dispensing
        @(posedge clk);
        #1;

        if (dispense == 1'b1 && change_amount == 8'd0)
            $display("TEST 1 PASS");
        else
            $display("TEST 1 FAIL: dispense=%b change=%d",
                     dispense, change_amount);

        repeat (3) @(posedge clk);


        //======================================================
        // TEST 2: Change return
        // Price = 7
        // Coin = 10
        // Expected: dispense = 1, change = 3
        //======================================================

        $display("");
        $display("========================================");
        $display("TEST 2: CHANGE RETURN");
        $display("========================================");

        item_price      = 8'd7;
        stock_available = 1'b1;

        insert_coin(8'd10);

        select_item();

        // Wait until dispensing
        @(posedge clk);
        #1;

        if (dispense == 1'b1)
            $display("TEST 2 DISPENSE PASS");
        else
            $display("TEST 2 DISPENSE FAIL");

        // Move to change return
        @(posedge clk);
        #1;

        if (change_amount == 8'd3)
            $display("TEST 2 CHANGE PASS: change=%d",
                     change_amount);
        else
            $display("TEST 2 CHANGE FAIL: change=%d",
                     change_amount);

        repeat (3) @(posedge clk);


        //======================================================
        // TEST 3: Out of stock
        // Price = 5
        // Coin = 5
        // Expected: error = 1, refund = 5
        //======================================================

        $display("");
        $display("========================================");
        $display("TEST 3: OUT OF STOCK");
        $display("========================================");

        item_price      = 8'd5;
        stock_available = 1'b0;

        insert_coin(8'd5);

        select_item();

        @(posedge clk);
        #1;

        if (error == 1'b1)
            $display("TEST 3 ERROR PASS");
        else
            $display("TEST 3 ERROR FAIL");

        if (change_amount == 8'd5)
            $display("TEST 3 REFUND PASS: refund=%d",
                     change_amount);
        else
            $display("TEST 3 REFUND FAIL: refund=%d",
                     change_amount);

        repeat (3) @(posedge clk);


        //======================================================
        // TEST 4: Insufficient balance
        // Price = 10
        // Coin = 5
        // Expected: no dispensing
        //======================================================

        $display("");
        $display("========================================");
        $display("TEST 4: INSUFFICIENT BALANCE");
        $display("========================================");

        item_price      = 8'd10;
        stock_available = 1'b1;

        insert_coin(8'd5);

        select_item();

        repeat (2) @(posedge clk);
        #1;

        if (dispense == 1'b0 && error == 1'b0)
            $display("TEST 4 PASS: No dispensing");
        else
            $display("TEST 4 FAIL");

        repeat (3) @(posedge clk);


        //======================================================
        // TEST 5: Multiple denominations
        // Price = 13
        // Coins = 10 + 2 + 1
        // Expected: dispense = 1, change = 0
        //======================================================

        $display("");
        $display("========================================");
        $display("TEST 5: MULTIPLE DENOMINATIONS");
        $display("========================================");

        item_price      = 8'd13;
        stock_available = 1'b1;

        insert_coin(8'd10);
        insert_coin(8'd2);
        insert_coin(8'd1);

        select_item();

        @(posedge clk);
        #1;

        if (dispense == 1'b1 && change_amount == 8'd0)
            $display("TEST 5 PASS");
        else
            $display("TEST 5 FAIL: dispense=%b change=%d",
                     dispense, change_amount);

        repeat (3) @(posedge clk);


        //======================================================
        // TEST 6: 1-unit coin
        // Price = 1
        // Coin = 1
        //======================================================

        $display("");
        $display("========================================");
        $display("TEST 6: 1 UNIT COIN");
        $display("========================================");

        item_price      = 8'd1;
        stock_available = 1'b1;

        insert_coin(8'd1);

        select_item();

        @(posedge clk);
        #1;

        if (dispense == 1'b1)
            $display("TEST 6 PASS");
        else
            $display("TEST 6 FAIL");

        repeat (3) @(posedge clk);


        //======================================================
        // TEST 7: 2-unit coin
        // Price = 2
        // Coin = 2
        //======================================================

        $display("");
        $display("========================================");
        $display("TEST 7: 2 UNIT COIN");
        $display("========================================");

        item_price      = 8'd2;
        stock_available = 1'b1;

        insert_coin(8'd2);

        select_item();

        @(posedge clk);
        #1;

        if (dispense == 1'b1)
            $display("TEST 7 PASS");
        else
            $display("TEST 7 FAIL");

        repeat (3) @(posedge clk);


        //======================================================
        // TEST 8: 5-unit coin
        // Price = 5
        // Coin = 5
        //======================================================

        $display("");
        $display("========================================");
        $display("TEST 8: 5 UNIT COIN");
        $display("========================================");

        item_price      = 8'd5;
        stock_available = 1'b1;

        insert_coin(8'd5);

        select_item();

        @(posedge clk);
        #1;

        if (dispense == 1'b1)
            $display("TEST 8 PASS");
        else
            $display("TEST 8 FAIL");

        repeat (3) @(posedge clk);


        //======================================================
        // FINISH
        //======================================================

        $display("");
        $display("========================================");
        $display("ALL TESTS COMPLETED");
        $display("========================================");

        $finish;
    end

    //==========================================================
    // Monitor
    //==========================================================
    initial begin
        $monitor(
            "TIME=%0t | RST=%b | COIN=%b | VALUE=%d | SELECT=%b | PRICE=%d | STOCK=%b | DISPENSE=%b | CHANGE=%d | ERROR=%b",
            $time,
            rst,
            coin_valid,
            coin_value,
            item_select,
            item_price,
            stock_available,
            dispense,
            change_amount,
            error
        );
    end

endmodule
