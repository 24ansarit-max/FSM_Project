`timescale 1ns/1ps

module tb_elevator_fsm;

    //====================================================
    // Signals
    //====================================================

    logic clk;
    logic rst;

    logic [3:0] floor_request;
    logic [1:0] current_floor;
    logic door_obstacle;

    logic motor_up;
    logic motor_down;
    logic door_open;
    logic door_close;
    logic [1:0] floor_indicator;


    //====================================================
    // DUT
    //====================================================

    elevator_fsm dut (
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
    // 100 MHz CLOCK
    //====================================================

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end


    //====================================================
    // CHECK TASK
    //====================================================

    task check_outputs;
        input expected_up;
        input expected_down;
        input expected_open;
        input expected_close;

        begin

            if ((motor_up    == expected_up)    &&
                (motor_down  == expected_down)  &&
                (door_open  == expected_open)   &&
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
    // TEST SEQUENCE
    //====================================================

    initial begin

        // Initial values
        rst            = 1'b1;
        floor_request  = 4'b0000;
        current_floor  = 2'd0;
        door_obstacle  = 1'b0;


        //================================================
        // TEST 1 : RESET
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 1 : RESET");
        $display("========================================");

        repeat (2)
            @(posedge clk);

        #1;

        check_outputs(0, 0, 0, 0);

        rst = 1'b0;

        @(posedge clk);
        #1;


        //================================================
        // TEST 2 : CURRENT FLOOR REQUEST
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 2 : CURRENT FLOOR REQUEST");
        $display("========================================");

        // Elevator is at floor 0
        floor_request = 4'b0001;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        // IDLE -> DOOR_OPENING
        @(posedge clk);
        #1;

        check_outputs(0, 0, 1, 0);

        // Door opening timer
        repeat (3)
            @(posedge clk);

        #1;

        check_outputs(0, 0, 1, 0);


        //================================================
        // TEST 3 : DOOR OPEN
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 3 : DOOR OPEN");
        $display("========================================");

        repeat (2)
            @(posedge clk);

        #1;

        check_outputs(0, 0, 1, 0);


        //================================================
        // TEST 4 : DOOR CLOSING
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 4 : DOOR CLOSING");
        $display("========================================");

        repeat (5)
            @(posedge clk);

        #1;

        check_outputs(0, 0, 0, 1);


        //================================================
        // TEST 5 : MOVE UP
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 5 : MOVE UP");
        $display("========================================");

        repeat (3)
            @(posedge clk);

        #1;

        // Request floor 3
        floor_request = 4'b1000;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        check_outputs(1, 0, 0, 0);


        //================================================
        // TEST 6 : MOVE DOWN
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 6 : MOVE DOWN");
        $display("========================================");

        // Put elevator at floor 3
        current_floor = 2'd3;

        floor_request = 4'b0001;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        check_outputs(0, 1, 0, 0);


        //================================================
        // TEST 7 : DOOR OBSTRUCTION
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 7 : DOOR OBSTRUCTION");
        $display("========================================");

        // Request current floor
        current_floor = 2'd3;
        floor_request = 4'b1000;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        // Wait for door opening
        repeat (4)
            @(posedge clk);

        // Wait until door is open
        repeat (4)
            @(posedge clk);

        // Obstacle detected
        door_obstacle = 1'b1;

        @(posedge clk);
        #1;

        $display("Door obstacle = 1");

        check_outputs(0, 0, 1, 0);

        // Remove obstacle
        door_obstacle = 1'b0;


        //================================================
        // TEST 8 : FLOOR INDICATOR
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 8 : FLOOR INDICATOR");
        $display("========================================");

        current_floor = 2'd2;

        #1;

        if (floor_indicator == 2'd2)
            $display("PASS: Floor indicator = %0d", floor_indicator);
        else
            $display(
                "FAIL: Expected floor indicator = 2, Got = %0d",
                floor_indicator
            );


        //================================================
        // TEST 9 : MULTIPLE REQUESTS
        //================================================

        $display("");
        $display("========================================");
        $display("TEST 9 : MULTIPLE REQUESTS");
        $display("========================================");

        current_floor = 2'd1;

        floor_request = 4'b1001;

        @(posedge clk);
        #1;

        floor_request = 4'b0000;

        @(posedge clk);
        #1;

        $display(
            "Multiple requests applied: 1001"
        );


        //================================================
        // END
        //================================================

        $display("");
        $display("========================================");
        $display("SIMULATION COMPLETED");
        $display("========================================");

        #20;

        $finish;

    end

endmodule
