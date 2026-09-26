`timescale 1ns/1ps

module tb_microwave_controller;

    //====================================================
    // Inputs
    //====================================================
    logic clk;
    logic reset;
    logic door_open;
    logic start;
    logic stop;
    logic [15:0] time_set;

    //====================================================
    // Outputs
    //====================================================
    logic magnetron;
    logic turntable;
    logic light;
    logic cooking;
    logic done;

    //====================================================
    // DUT
    //====================================================
    microwave_controller #(
        .TIMER_WIDTH(16)
    ) dut (
        .clk       (clk),
        .reset     (reset),
        .door_open (door_open),
        .start     (start),
        .stop      (stop),
        .time_set  (time_set),

        .magnetron (magnetron),
        .turntable (turntable),
        .light     (light),
        .cooking   (cooking),
        .done      (done)
    );

    //====================================================
    // Clock: 10 ns
    //====================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //====================================================
    // Test task
    //====================================================
    task check_output(
        input logic exp_magnetron,
        input logic exp_turntable,
        input logic exp_light,
        input logic exp_cooking,
        input logic exp_done,
        input [200*8:1] test_name
    );
        begin
            #1;

            if ((magnetron === exp_magnetron) &&
                (turntable === exp_turntable) &&
                (light     === exp_light) &&
                (cooking   === exp_cooking) &&
                (done      === exp_done)) begin

                $display("PASS: %s", test_name);

            end
            else begin

                $display("FAIL: %s", test_name);

                $display("Expected: M=%b T=%b L=%b C=%b D=%b",
                         exp_magnetron,
                         exp_turntable,
                         exp_light,
                         exp_cooking,
                         exp_done);

                $display("Actual:   M=%b T=%b L=%b C=%b D=%b",
                         magnetron,
                         turntable,
                         light,
                         cooking,
                         done);
            end
        end
    endtask

    //====================================================
    // Test sequence
    //====================================================
    initial begin

        $display("==============================================");
        $display("       MICROWAVE CONTROLLER TESTBENCH");
        $display("==============================================");

        // Initial values
        reset     = 1'b1;
        door_open = 1'b0;
        start     = 1'b0;
        stop      = 1'b0;
        time_set  = 16'd0;

        //================================================
        // TEST 1: RESET
        //================================================

        @(posedge clk);
        #1;

        check_output(
            1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
            "Reset"
        );

        reset = 1'b0;

        //================================================
        // TEST 2: IDLE
        //================================================

        @(posedge clk);

        check_output(
            1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
            "Idle"
        );

        //================================================
        // TEST 3: START COOKING
        //================================================

        time_set = 16'd5;
        start    = 1'b1;

        @(posedge clk);

        start = 1'b0;

        // State changes to COOKING
        @(posedge clk);

        check_output(
            1'b1, 1'b1, 1'b1, 1'b1, 1'b0,
            "Start cooking"
        );

        //================================================
        // TEST 4: NORMAL COOKING
        //================================================

        @(posedge clk);

        check_output(
            1'b1, 1'b1, 1'b1, 1'b1, 1'b0,
            "Normal cooking"
        );

        //================================================
        // TEST 5: OPEN DOOR DURING COOKING
        //================================================

        door_open = 1'b1;

        @(posedge clk);

        check_output(
            1'b0, 1'b0, 1'b1, 1'b0, 1'b0,
            "Door open - magnetron OFF"
        );

        //================================================
        // TEST 6: SAFETY INTERLOCK
        //================================================

        #1;

        if (magnetron == 1'b0)
            $display("PASS: Safety interlock");
        else
            $display("FAIL: Magnetron ON with door open");

        //================================================
        // TEST 7: CLOSE DOOR
        //================================================

        door_open = 1'b0;

        @(posedge clk);

        check_output(
            1'b0, 1'b0, 1'b1, 1'b0, 1'b0,
            "Door closed - remain paused"
        );

        //================================================
        // TEST 8: RESUME
        //================================================

        start = 1'b1;

        @(posedge clk);

        start = 1'b0;

        @(posedge clk);

        check_output(
            1'b1, 1'b1, 1'b1, 1'b1, 1'b0,
            "Resume cooking"
        );

        //================================================
        // TEST 9: STOP
        //================================================

        stop = 1'b1;

        @(posedge clk);

        stop = 1'b0;

        @(posedge clk);

        check_output(
            1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
            "Stop cooking"
        );

        //================================================
        // TEST 10: TIMER = 0
        //================================================

        time_set = 16'd0;
        start    = 1'b1;

        @(posedge clk);

        start = 1'b0;

        @(posedge clk);

        check_output(
            1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
            "Zero timer cannot start"
        );

        //================================================
        // TEST 11: START NEW COOKING CYCLE
        //================================================

        time_set = 16'd3;
        start    = 1'b1;

        @(posedge clk);

        start = 1'b0;

        @(posedge clk);

        check_output(
            1'b1, 1'b1, 1'b1, 1'b1, 1'b0,
            "New cooking cycle"
        );

        //================================================
        // TEST 12: TIMER COMPLETION
        //================================================

        // Your DUT decrements the timer every clock,
        // so wait enough cycles for timer to reach 1.

        repeat (3) @(posedge clk);

        check_output(
            1'b0, 1'b0, 1'b1, 1'b0, 1'b1,
            "Timer complete - DONE"
        );

        //================================================
        // TEST 13: RESTART AFTER DONE
        //================================================

        time_set = 16'd2;
        start    = 1'b1;

        @(posedge clk);

        start = 1'b0;

        @(posedge clk);

        check_output(
            1'b1, 1'b1, 1'b1, 1'b1, 1'b0,
            "Restart after DONE"
        );

        //================================================
        // TEST 14: OPEN DOOR AGAIN
        //================================================

        door_open = 1'b1;

        @(posedge clk);

        check_output(
            1'b0, 1'b0, 1'b1, 1'b0, 1'b0,
            "Door open safety test"
        );

        //================================================
        // END
        //================================================

        $display("");
        $display("==============================================");
        $display("             TEST COMPLETED");
        $display("==============================================");

        $finish;

    end

endmodule
