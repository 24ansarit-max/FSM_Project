`timescale 1ns/1ps

module tb_elevator_controller;

    parameter int NUM_FLOORS = 4;
    parameter int FLOOR_W = $clog2(NUM_FLOORS);

    logic clk;
    logic rst_n;
    logic [NUM_FLOORS-1:0] floor_request;
    logic door_obstacle;

    logic motor_up;
    logic motor_down;
    logic door_open;
    logic [FLOOR_W-1:0] current_floor;

    integer pass_count;
    integer fail_count;
    integer i;

    elevator_controller #(
        .NUM_FLOORS(NUM_FLOORS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .floor_request(floor_request),
        .door_obstacle(door_obstacle),
        .motor_up(motor_up),
        .motor_down(motor_down),
        .door_open(door_open),
        .current_floor(current_floor)
    );

    // Clock
    initial begin
        clk = 0;
        forever #20 clk = ~clk;
    end

    // --------------------------------------------------
    // PASS / FAIL checker
    // --------------------------------------------------
    task check;
        input condition;
        input [255:0] message;

        begin
            if (condition) begin
                $display("PASS: %s", message);
                pass_count = pass_count + 1;
            end
            else begin
                $display("FAIL: %s", message);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // --------------------------------------------------
    // Reset
    // --------------------------------------------------
    task reset_dut;
        begin
            rst_n = 0;
            floor_request = 0;
            door_obstacle = 0;

            repeat (3)
                @(posedge clk);

            rst_n = 1;

            @(posedge clk);
            #20;

            check(current_floor == 0,
                  "Elevator starts at floor 0");

            check(motor_up == 0 &&
                  motor_down == 0 &&
                  door_open == 0,
                  "All outputs OFF after reset");
        end
    endtask

    // --------------------------------------------------
    // Request a floor
    // --------------------------------------------------
    task request_floor;
        input integer target_floor;

        integer timeout;
        reg reached;

        begin
            $display("");
            $display("----------------------------------------");
            $display("Requesting floor %0d", target_floor);
            $display("----------------------------------------");

            reached = 0;
            timeout = 0;

            @(negedge clk);
            floor_request = (1 << target_floor);

            @(negedge clk);
            floor_request = 0;

            while ((timeout < 30) && (reached == 0)) begin

                @(posedge clk);
                #20;

                $display("Time=%0t Floor=%0d UP=%b DOWN=%b DOOR=%b",
                         $time,
                         current_floor,
                         motor_up,
                         motor_down,
                         door_open);

                if (door_open == 1)
                    reached = 1;

                timeout = timeout + 1;
            end

            if (reached == 0) begin
                $display("FAIL: Timeout waiting for floor %0d",
                         target_floor);
                fail_count = fail_count + 1;
            end
            else begin
                check(current_floor == target_floor,
                      "Reached requested floor");

                check(door_open == 1,
                      "Door opened at requested floor");

                check(motor_up == 0 &&
                      motor_down == 0,
                      "Motors OFF when door is open");
            end

            @(posedge clk);
            #20;
        end
    endtask

    // --------------------------------------------------
    // UP motion test
    // --------------------------------------------------
    task test_up_motion;

        integer timeout;
        reg up_seen;
        reg door_seen;

        begin
            $display("");
            $display("----------------------------------------");
            $display("TEST: UP MOTION");
            $display("----------------------------------------");

            up_seen = 0;
            door_seen = 0;
            timeout = 0;

            check(current_floor == 0,
                  "Elevator is at floor 0");

            @(negedge clk);
            floor_request = 4'b1000;

            @(negedge clk);
            floor_request = 0;

            while ((timeout < 20) && (door_seen == 0)) begin

                @(posedge clk);
                #20;

                if (motor_up == 1)
                    up_seen = 1;

                if (door_open == 1)
                    door_seen = 1;

                timeout = timeout + 1;
            end

            check(up_seen == 1,
                  "Motor UP activated");

            check(motor_down == 0,
                  "Motor DOWN remains OFF during UP");

            check(current_floor == 3,
                  "Elevator reaches floor 3");

            check(door_seen == 1,
                  "Door opens at floor 3");
        end
    endtask

    // --------------------------------------------------
    // DOWN motion test
    // --------------------------------------------------
    task test_down_motion;

        integer timeout;
        reg down_seen;
        reg door_seen;

        begin
            $display("");
            $display("----------------------------------------");
            $display("TEST: DOWN MOTION");
            $display("----------------------------------------");

            down_seen = 0;
            door_seen = 0;
            timeout = 0;

            @(negedge clk);
            floor_request = 4'b0010;

            @(negedge clk);
            floor_request = 0;

            while ((timeout < 20) && (door_seen == 0)) begin

                @(posedge clk);
                #20;

                if (motor_down == 1)
                    down_seen = 1;

                if (door_open == 1)
                    door_seen = 1;

                timeout = timeout + 1;
            end

            check(down_seen == 1,
                  "Motor DOWN activated");

            check(motor_up == 0,
                  "Motor UP remains OFF during DOWN");

            check(current_floor == 1,
                  "Elevator reaches floor 1");

            check(door_seen == 1,
                  "Door opens at floor 1");
        end
    endtask

    // --------------------------------------------------
    // Door obstacle test
    // --------------------------------------------------
    task test_obstacle;

        integer timeout;
        reg door_seen;

        begin
            $display("");
            $display("----------------------------------------");
            $display("TEST: DOOR OBSTACLE");
            $display("----------------------------------------");

            door_seen = 0;
            timeout = 0;

            @(negedge clk);
            floor_request = 4'b0100;

            @(negedge clk);
            floor_request = 0;

            while ((timeout < 20) && (door_seen == 0)) begin

                @(posedge clk);
                #20;

                if (door_open == 1)
                    door_seen = 1;

                timeout = timeout + 1;
            end

            check(door_seen == 1,
                  "Door opened at floor 2");

            // Activate obstacle
            @(negedge clk);
            door_obstacle = 1;

            repeat (3) begin
                @(posedge clk);
                #20;

                check(door_open == 1,
                      "Door remains open with obstacle");
            end

            // Remove obstacle
            @(negedge clk);
            door_obstacle = 0;

            @(posedge clk);
            #20;

            $display("Obstacle removed");

            @(posedge clk);
            #20;

            check(door_open == 0,
                  "Door closes after obstacle is removed");
        end
    endtask

    // --------------------------------------------------
    // Multiple requests
    // --------------------------------------------------
    task test_multiple_requests;

        integer timeout;
        reg door_seen;

        begin
            $display("");
            $display("----------------------------------------");
            $display("TEST: MULTIPLE REQUESTS");
            $display("----------------------------------------");

            door_seen = 0;
            timeout = 0;

            // Request floors 0 and 3
            @(negedge clk);
            floor_request = 4'b1001;

            @(negedge clk);
            floor_request = 0;

            while ((timeout < 30) && (door_seen == 0)) begin

                @(posedge clk);
                #20;

                if (door_open == 1)
                    door_seen = 1;

                timeout = timeout + 1;
            end

            check(door_seen == 1,
                  "First pending request serviced");

            @(posedge clk);
            #20;

            // Wait for second request
            door_seen = 0;
            timeout = 0;

            while ((timeout < 30) && (door_seen == 0)) begin

                @(posedge clk);
                #20;

                if (door_open == 1)
                    door_seen = 1;

                timeout = timeout + 1;
            end

            check(door_seen == 1,
                  "Second pending request serviced");
        end
    endtask

    // --------------------------------------------------
    // Main test
    // --------------------------------------------------
    initial begin

        pass_count = 0;
        fail_count = 0;

        rst_n = 0;
        floor_request = 0;
        door_obstacle = 0;

        $display("");
        $display("============================================");
        $display("     ELEVATOR CONTROLLER TESTBENCH");
        $display("============================================");

        // Reset
        reset_dut();

        // Basic floor requests
        request_floor(1);
        request_floor(2);
        request_floor(3);

        // Down request
        request_floor(1);

        // Door obstacle
        test_obstacle();

        // Reset
        reset_dut();

        // UP test
        test_up_motion();

        // DOWN test
        test_down_motion();

        // Multiple requests
        reset_dut();
        test_multiple_requests();

        #20;

        $display("");
        $display("============================================");
        $display("              TEST SUMMARY");
        $display("============================================");
        $display("PASS COUNT = %0d", pass_count);
        $display("FAIL COUNT = %0d", fail_count);

        if (fail_count == 0)
            $display("******** ALL TESTS PASSED ********");
        else
            $display("******** TESTS FAILED ********");

        $display("============================================");

        $finish;
    end

endmodule
