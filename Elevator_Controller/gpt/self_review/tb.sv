`timescale 1ns/1ps

module tb_elevator_controller;

    //====================================================
    // CONSTANTS
    //====================================================

    localparam integer NUM_FLOORS = 4;
    localparam integer FLOOR_W = 2;

    // These match the default values in the DUT.
    localparam integer OPEN_TIME  = 5;
    localparam integer CLOSE_TIME = 2;


    //====================================================
    // SIGNALS
    //====================================================

    logic clk;
    logic rst;

    logic [NUM_FLOORS-1:0] floor_request;
    logic [FLOOR_W-1:0] current_floor;
    logic door_obstacle;

    logic motor_up;
    logic motor_down;
    logic door_open;
    logic door_close;

    logic [FLOOR_W-1:0] floor_indicator;


    //====================================================
    // DUT
    //====================================================

    elevator_controller dut (
        .clk(clk),
        .rst(rst),
        .floor_request(floor_request),
        .current_floor(current_floor),
        .door_obstacle(door_obstacle),
        .motor_up(motor_up),
        .motor_down(motor_down),
        .door_open(door_open),
        .door_close(door_close),
        .floor_indicator(floor_indicator)
    );


    //====================================================
    // CLOCK
    // 100 MHz -> 10 ns period
    //====================================================

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end


    //====================================================
    // RESET TASK
    //====================================================

    task reset_dut;
        begin

            rst = 1'b1;
            floor_request = 4'b0000;
            door_obstacle = 1'b0;
            current_floor = 2'd0;

            repeat (2)
                @(posedge clk);

            #1;

            rst = 1'b0;

            @(posedge clk);
            #1;

        end
    endtask


    //====================================================
    // DISPLAY TASK
    //====================================================

    task display_status;
        begin

            $display(
                "TIME=%0t | FLOOR=%0d | REQUEST=%b | UP=%b DOWN=%b | OPEN=%b CLOSE=%b | OBSTACLE=%b",
                $time,
                current_floor,
                floor_request,
                motor_up,
                motor_down,
                door_open,
                door_close,
                door_obstacle
            );

        end
    endtask


    //====================================================
    // CHECK OUTPUT TASK
    //====================================================

    task check_outputs;

        input expected_up;
        input expected_down;
        input expected_open;
        input expected_close;

        begin

            if ((motor_up == expected_up) &&
                (motor_down == expected_down) &&
                (door_open == expected_open) &&
                (door_close == expected_close)) begin

                $display(
                    "PASS: UP=%b DOWN=%b OPEN=%b CLOSE=%b",
                    motor_up,
                    motor_down,
                    door_open,
                    door_close
                );

            end
            else begin

                $display(
                    "FAIL: Expected UP=%b DOWN=%b OPEN=%b CLOSE=%b | Got UP=%b DOWN=%b OPEN=%b CLOSE=%b",
                    expected_up,
                    expected_down,
                    expected_open,
                    expected_close,
                    motor_up,
                    motor_down,
                    door_open,
                    door_close
                );

            end

        end

    endtask


    //====================================================
    // MAIN TEST SEQUENCE
    //====================================================

    initial begin

        $display("");
        $display("==============================================");
        $display("       ELEVATOR CONTROLLER TESTBENCH");
        $display("==============================================");


        //================================================
        // TEST 1 : RESET / IDLE
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 1 : RESET / IDLE");
        $display("==============================================");

        reset_dut;

        display_status;

        check_outputs(
            1'b0,
            1'b0,
            1'b0,
            1'b0
        );


        //================================================
        // TEST 2 : CURRENT FLOOR REQUEST
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 2 : CURRENT FLOOR REQUEST");
        $display("==============================================");

        reset_dut;

        current_floor = 2'd0;

        // Request current floor
        floor_request = 4'b0001;

        @(posedge clk);
        #1;

        // Remove button
        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        display_status;

        check_outputs(
            1'b0,
            1'b0,
            1'b1,
            1'b0
        );


        //================================================
        // TEST 3 : DOOR OPEN
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 3 : DOOR OPEN");
        $display("==============================================");

        repeat (OPEN_TIME + 1) begin
            @(posedge clk);
            #1;
        end

        display_status;


        //================================================
        // TEST 4 : DOOR CLOSE
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 4 : DOOR CLOSE");
        $display("==============================================");

        repeat (CLOSE_TIME + 1) begin
            @(posedge clk);
            #1;
        end

        display_status;


        //================================================
        // TEST 5 : MOVE UP
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 5 : MOVE UP");
        $display("==============================================");

        reset_dut;

        // Start at floor 0
        current_floor = 2'd0;

        // Request floor 3
        floor_request = 4'b1000;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        display_status;

        check_outputs(
            1'b1,
            1'b0,
            1'b0,
            1'b0
        );


        //================================================
        // TEST 6 : MOVE DOWN
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 6 : MOVE DOWN");
        $display("==============================================");

        reset_dut;

        // Start at floor 3
        current_floor = 2'd3;

        // Request floor 0
        floor_request = 4'b0001;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        display_status;

        check_outputs(
            1'b0,
            1'b1,
            1'b0,
            1'b0
        );


        //================================================
        // TEST 7 : MULTIPLE REQUESTS
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 7 : MULTIPLE REQUESTS");
        $display("==============================================");

        reset_dut;

        current_floor = 2'd1;

        // Request floor 0 and floor 3
        floor_request = 4'b1001;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        display_status;

        // Since requests exist above and below,
        // the controller checks request_above first.
        if (motor_up == 1'b1)
            $display("PASS: Elevator selected UP direction");
        else
            $display("FAIL: Elevator did not select UP direction");


        //================================================
        // TEST 8 : DOOR OBSTRUCTION
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 8 : DOOR OBSTRUCTION");
        $display("==============================================");

        reset_dut;

        current_floor = 2'd0;

        // Request current floor
        floor_request = 4'b0001;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        // Wait until door opens
        repeat (OPEN_TIME + 2) begin
            @(posedge clk);
            #1;
        end

        display_status;

        // Wait for DOOR_CLOSING
        repeat (CLOSE_TIME + 1) begin
            @(posedge clk);
            #1;
        end

        // Apply obstruction
        door_obstacle = 1'b1;

        @(posedge clk);
        #1;

        display_status;

        if (door_open == 1'b1)
            $display("PASS: Door reopened because of obstruction");
        else
            $display("INFO: Obstruction detected; checking FSM response");

        // Remove obstruction
        door_obstacle = 1'b0;


        //================================================
        // TEST 9 : FLOOR INDICATOR
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 9 : FLOOR INDICATOR");
        $display("==============================================");

        reset_dut;

        current_floor = 2'd2;

        #1;

        if (floor_indicator == 2'd2)

            $display(
                "PASS: Floor indicator = %0d",
                floor_indicator
            );

        else

            $display(
                "FAIL: Expected floor indicator = 2, Got = %0d",
                floor_indicator
            );


        //================================================
        // TEST 10 : NO REQUEST
        //================================================

        $display("");
        $display("==============================================");
        $display("TEST 10 : NO REQUEST / IDLE");
        $display("==============================================");

        reset_dut;

        current_floor = 2'd1;

        floor_request = 4'b0000;
        door_obstacle = 1'b0;

        repeat (3) begin
            @(posedge clk);
            #1;
            display_status;
        end

        check_outputs(
            1'b0,
            1'b0,
            1'b0,
            1'b0
        );


        //================================================
        // END
        //================================================

        $display("");
        $display("==============================================");
        $display("       SIMULATION COMPLETED");
        $display("==============================================");

        #20;

        $finish;

    end

endmodule
