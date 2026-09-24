`timescale 1ns/1ps

module tb_elevator_controller;

    parameter NUM_FLOORS = 4;
    parameter OPEN_TIME = 10;
    parameter CLOSE_TIME = 10;

    //====================================================
    // INPUTS
    //====================================================

    logic clk;
    logic rst_n;

    logic [NUM_FLOORS-1:0] floor_request;

    logic [$clog2(NUM_FLOORS)-1:0] current_floor_sensor;

    logic up_limit;
    logic down_limit;

    logic door_sensor;


    //====================================================
    // OUTPUTS
    //====================================================

    logic motor_up;
    logic motor_down;

    logic door_open;
    logic door_close;

    logic [$clog2(NUM_FLOORS)-1:0] current_floor_display;

    logic direction_up;
    logic direction_down;


    //====================================================
    // DUT
    //====================================================

    elevator_controller #(
        .NUM_FLOORS(NUM_FLOORS),
        .OPEN_TIME(OPEN_TIME),
        .CLOSE_TIME(CLOSE_TIME)
    ) dut (

        .clk(clk),
        .rst_n(rst_n),

        .floor_request(floor_request),

        .current_floor_sensor(current_floor_sensor),

        .up_limit(up_limit),
        .down_limit(down_limit),

        .door_sensor(door_sensor),

        .motor_up(motor_up),
        .motor_down(motor_down),

        .door_open(door_open),
        .door_close(door_close),

        .current_floor_display(current_floor_display),

        .direction_up(direction_up),
        .direction_down(direction_down)
    );


    //====================================================
    // 100 MHz CLOCK
    // 10 ns period
    //====================================================

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end


    //====================================================
    // DISPLAY STATUS
    //====================================================

    task show_status;
        begin

            $display(
                "TIME=%0t | FLOOR=%0d | REQUEST=%b | UP=%b DOWN=%b | OPEN=%b CLOSE=%b | SENSOR=%b",
                $time,
                current_floor_display,
                floor_request,
                motor_up,
                motor_down,
                door_open,
                door_close,
                door_sensor
            );

        end
    endtask


    //====================================================
    // TEST 1 : RESET
    //====================================================

    initial begin

        $display("");
        $display("========================================");
        $display("ELEVATOR CONTROLLER TESTBENCH");
        $display("========================================");


        rst_n = 1'b0;

        floor_request = 4'b0000;

        current_floor_sensor = 2'd0;

        up_limit = 1'b0;
        down_limit = 1'b0;

        door_sensor = 1'b0;


        $display("");
        $display("========================================");
        $display("TEST 1 : RESET");
        $display("========================================");

        repeat (2)
            @(posedge clk);

        #1;

        show_status;

        rst_n = 1'b1;


        //================================================
        // TEST 2 : CURRENT FLOOR REQUEST
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 2 : CURRENT FLOOR REQUEST");
        $display("========================================");

        // Elevator is at floor 0
        current_floor_sensor = 2'd0;

        // Request floor 0
        floor_request = 4'b0001;

        @(posedge clk);
        #1;

        show_status;

        floor_request = 4'b0000;

        repeat (2)
            @(posedge clk);

        #1;

        show_status;


        //================================================
        // TEST 3 : MOVE UP
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 3 : MOVE UP TO FLOOR 3");
        $display("========================================");

        // Current floor = 0
        current_floor_sensor = 2'd0;

        // Request floor 3
        floor_request = 4'b1000;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        show_status;


        // Elevator moves to floor 1
        current_floor_sensor = 2'd1;

        @(posedge clk);
        #1;

        show_status;


        // Elevator moves to floor 2
        current_floor_sensor = 2'd2;

        @(posedge clk);
        #1;

        show_status;


        // Elevator reaches floor 3
        current_floor_sensor = 2'd3;

        @(posedge clk);
        #1;

        show_status;


        //================================================
        // TEST 4 : DOOR OPENING
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 4 : DOOR OPENING");
        $display("========================================");

        repeat (3) begin

            @(posedge clk);
            #1;

            show_status;

        end


        //================================================
        // TEST 5 : DOOR OPEN
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 5 : DOOR OPEN");
        $display("========================================");

        repeat (5) begin

            @(posedge clk);
            #1;

            show_status;

        end


        //================================================
        // TEST 6 : DOOR CLOSING
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 6 : DOOR CLOSING");
        $display("========================================");

        repeat (5) begin

            @(posedge clk);
            #1;

            show_status;

        end


        //================================================
        // TEST 7 : MOVE DOWN
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 7 : MOVE DOWN");
        $display("========================================");

        // Current floor = 3
        current_floor_sensor = 2'd3;

        // Request floor 1
        floor_request = 4'b0010;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        show_status;


        // Move to floor 2
        current_floor_sensor = 2'd2;

        @(posedge clk);
        #1;

        show_status;


        // Move to floor 1
        current_floor_sensor = 2'd1;

        @(posedge clk);
        #1;

        show_status;


        //================================================
        // TEST 8 : DOOR OBSTRUCTION
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 8 : DOOR OBSTRUCTION");
        $display("========================================");

        // Request current floor
        floor_request = 4'b0010;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        repeat (3) begin

            @(posedge clk);
            #1;

            show_status;

        end


        // Obstruction detected
        door_sensor = 1'b1;

        $display("DOOR OBSTACLE = 1");

        repeat (2) begin

            @(posedge clk);
            #1;

            show_status;

        end


        // Remove obstruction
        door_sensor = 1'b0;

        $display("DOOR OBSTACLE = 0");


        //================================================
        // TEST 9 : MULTIPLE REQUESTS
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 9 : MULTIPLE FLOOR REQUESTS");
        $display("========================================");

        current_floor_sensor = 2'd1;

        // Request floors 0 and 3
        floor_request = 4'b1001;

        @(posedge clk);
        #1;

        show_status;

        floor_request = 4'b0000;

        repeat (4) begin

            @(posedge clk);
            #1;

            show_status;

        end


        //================================================
        // TEST 10 : UP LIMIT
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 10 : UP LIMIT");
        $display("========================================");

        current_floor_sensor = 2'd3;

        up_limit = 1'b1;

        @(posedge clk);
        #1;

        show_status;

        up_limit = 1'b0;


        //================================================
        // TEST 11 : DOWN LIMIT
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 11 : DOWN LIMIT");
        $display("========================================");

        current_floor_sensor = 2'd0;

        down_limit = 1'b1;

        @(posedge clk);
        #1;

        show_status;

        down_limit = 1'b0;


        //================================================
        // FLOOR INDICATOR CHECK
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 12 : FLOOR INDICATOR");
        $display("========================================");

        current_floor_sensor = 2'd2;

        #1;

        if (current_floor_display == 2'd2)

            $display(
                "PASS: FLOOR DISPLAY = %0d",
                current_floor_display
            );

        else

            $display(
                "FAIL: Expected FLOOR = 2, Got = %0d",
                current_floor_display
            );


        //================================================
        // DIRECTION CHECK
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 13 : DIRECTION OUTPUTS");
        $display("========================================");

        current_floor_sensor = 2'd0;

        floor_request = 4'b1000;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        if (direction_up == 1'b1)

            $display("PASS: DIRECTION UP = 1");

        else

            $display("FAIL: DIRECTION UP = 0");


        //================================================
        // FINISH
        //================================================

        $display("");
        $display("========================================");
        $display("ALL TESTS COMPLETED");
        $display("========================================");

        #20;

        $finish;

    end

endmodule
