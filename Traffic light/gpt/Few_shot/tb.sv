`timescale 1ns/1ps

module testbench;

    localparam CLK_FREQ_HZ      = 10;
    localparam GREEN_TIME_SEC   = 2;
    localparam YELLOW_TIME_SEC  = 1;
    localparam ALL_RED_TIME_SEC = 1;

    localparam N_GREEN     = 4'd0;
    localparam N_YELLOW    = 4'd1;
    localparam E_GREEN     = 4'd2;
    localparam ALL_RED     = 4'd8;
    localparam FAULT_FLASH = 4'd9;

    logic clk = 0;
    logic rst;
    logic emergency_vehicle;
    logic fault_detect;
    logic [3:0] pedestrian_request;

    logic [2:0] light_N, light_E, light_S, light_W;
    logic [3:0] pedestrian_walk;

    integer errors = 0;
    integer checks = 0;

    always #5 clk = ~clk;

    traffic_controller_4way #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .GREEN_TIME_SEC(GREEN_TIME_SEC),
        .YELLOW_TIME_SEC(YELLOW_TIME_SEC),
        .ALL_RED_TIME_SEC(ALL_RED_TIME_SEC)
    ) dut (
        .clk(clk),
        .rst(rst),
        .emergency_vehicle(emergency_vehicle),
        .fault_detect(fault_detect),
        .pedestrian_request(pedestrian_request),
        .light_N(light_N),
        .light_E(light_E),
        .light_S(light_S),
        .light_W(light_W),
        .pedestrian_walk(pedestrian_walk)
    );

    // Check traffic-light outputs
    task automatic check_lights;
        input [2:0] exp_N;
        input [2:0] exp_E;
        input [2:0] exp_S;
        input [2:0] exp_W;
        input [8*60-1:0] test_name;
        begin
            checks = checks + 1;

            if (light_N !== exp_N ||
                light_E !== exp_E ||
                light_S !== exp_S ||
                light_W !== exp_W) begin

                errors = errors + 1;
                $display("FAIL: %0s", test_name);
                $display("  Actual   N=%b E=%b S=%b W=%b",
                         light_N, light_E, light_S, light_W);
                $display("  Expected N=%b E=%b S=%b W=%b",
                         exp_N, exp_E, exp_S, exp_W);
            end
            else begin
                $display("PASS: %0s", test_name);
            end
        end
    endtask

    // Wait for a state without using break
    task automatic wait_state;
        input [3:0] expected_state;
        input integer timeout_cycles;
        input [8*60-1:0] test_name;

        integer count;
        reg found;
        begin
            count = 0;
            found = 0;

            while ((count < timeout_cycles) && !found) begin
                @(negedge clk);
                if (dut.state === expected_state)
                    found = 1;
                count = count + 1;
            end

            checks = checks + 1;

            if (found)
                $display("PASS: %0s", test_name);
            else begin
                errors = errors + 1;
                $display("FAIL: %0s; expected state=%0d, actual=%0d",
                         test_name, expected_state, dut.state);
            end
        end
    endtask

    // Check mutual exclusion of green lights
    task automatic check_green_exclusion;
        integer green_count;
        begin
            green_count = 0;

            if (light_N[0] === 1'b1) green_count = green_count + 1;
            if (light_E[0] === 1'b1) green_count = green_count + 1;
            if (light_S[0] === 1'b1) green_count = green_count + 1;
            if (light_W[0] === 1'b1) green_count = green_count + 1;

            checks = checks + 1;

            if (green_count > 1) begin
                errors = errors + 1;
                $display("FAIL: multiple green lights active");
            end
        end
    endtask

    always @(negedge clk) begin
        if (rst === 1'b0)
            check_green_exclusion();
    end

    initial begin
        $dumpfile("traffic_controller.vcd");
        $dumpvars(0, testbench);

        rst = 1'b1;
        emergency_vehicle = 1'b0;
        fault_detect = 1'b0;
        pedestrian_request = 4'b0000;

        $display("\n===== TRAFFIC CONTROLLER TEST START =====");

        // TEST 1: Reset
        repeat (3) @(negedge clk);
        #1;

        check_lights(3'b100, 3'b100, 3'b100, 3'b100,
                    "Reset: all lights red");

        rst = 1'b0;

        // TEST 2: Normal sequence
        wait_state(N_GREEN, 10, "North green");
        #1;
        check_lights(3'b001, 3'b100, 3'b100, 3'b100,
                    "North green output");

        wait_state(N_YELLOW, 30, "North yellow");
        #1;
        check_lights(3'b010, 3'b100, 3'b100, 3'b100,
                    "North yellow output");

        wait_state(ALL_RED, 20, "All red after North yellow");
        #1;
        check_lights(3'b100, 3'b100, 3'b100, 3'b100,
                    "All-red clearance");

        wait_state(E_GREEN, 20, "East green");
        #1;
        check_lights(3'b100, 3'b001, 3'b100, 3'b100,
                    "East green output");

        // TEST 3: Emergency override
        @(negedge clk);
        emergency_vehicle = 1'b1;
        #1;

        check_lights(3'b100, 3'b100, 3'b100, 3'b100,
                    "Emergency forces all red");

        wait_state(ALL_RED, 5, "Emergency all-red state");

        @(negedge clk);
        emergency_vehicle = 1'b0;

        wait_state(N_GREEN, 30, "Resume normal traffic sequence");

        // TEST 4: Pedestrian output
        @(negedge clk);
        pedestrian_request = 4'b0001;

        wait_state(N_GREEN, 5, "North green for pedestrian");
        #1;

        checks = checks + 1;
        if (pedestrian_walk[0] === 1'b1)
            $display("PASS: North pedestrian walk asserted");
        else begin
            errors = errors + 1;
            $display("FAIL: North pedestrian walk not asserted");
        end

        @(negedge clk);
        pedestrian_request = 4'b0000;
        #1;

        checks = checks + 1;
        if (pedestrian_walk === 4'b0000)
            $display("PASS: pedestrian walk clears without requests");
        else begin
            errors = errors + 1;
            $display("FAIL: pedestrian walk did not clear");
        end

        // TEST 5: Fault mode
        @(negedge clk);
        fault_detect = 1'b1;

        wait_state(FAULT_FLASH, 5, "Fault flash state");
        #1;

        checks = checks + 1;
        if (light_N[0] || light_E[0] ||
            light_S[0] || light_W[0]) begin
            errors = errors + 1;
            $display("FAIL: green output active during fault");
        end
        else
            $display("PASS: no green outputs during fault");

        // Check the flashing red output changes
        begin : fault_flash_check
            reg [2:0] saved_light;
            saved_light = light_N;

            repeat (12) @(negedge clk);
            #1;

            checks = checks + 1;
            if (light_N !== saved_light)
                $display("PASS: fault red output toggled");
            else begin
                errors = errors + 1;
                $display("FAIL: fault red output did not toggle");
            end
        end

        // Release fault
        @(negedge clk);
        fault_detect = 1'b0;

        wait_state(ALL_RED, 5, "Fault recovery through all red");
        #1;
        check_lights(3'b100, 3'b100, 3'b100, 3'b100,
                    "All red after fault recovery");

        // TEST SUMMARY
        repeat (3) @(negedge clk);

        $display("\n========== TEST SUMMARY ==========");
        $display("Total checks: %0d", checks);
        $display("Total errors: %0d", errors);

        if (errors == 0)
            $display("OVERALL RESULT: PASS");
        else
            $display("OVERALL RESULT: FAIL");

        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: Simulation timeout");
        $finish;
    end

endmodule
