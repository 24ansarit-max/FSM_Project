
`timescale 1ns/1ps

module testbench;

    // Short timing values for simulation
    localparam CLK_FREQ_HZ      = 10;
    localparam GREEN_TIME_SEC   = 3;
    localparam YELLOW_TIME_SEC  = 2;
    localparam ALL_RED_TIME_SEC = 1;
    localparam FAULT_FLASH_HZ   = 1;

    logic clk;
    logic rst;
    logic emergency_vehicle;
    logic fault_detect;
    logic [3:0] pedestrian_request;

    wire [2:0] light_N;
    wire [2:0] light_E;
    wire [2:0] light_S;
    wire [2:0] light_W;
    wire [3:0] pedestrian_walk;

    localparam RED    = 3'b100;
    localparam YELLOW = 3'b010;
    localparam GREEN  = 3'b001;

    integer errors;

    // DUT: matches the uploaded design ports
    traffic_controller_4way #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .GREEN_TIME_SEC(GREEN_TIME_SEC),
        .YELLOW_TIME_SEC(YELLOW_TIME_SEC),
        .ALL_RED_TIME_SEC(ALL_RED_TIME_SEC),
        .FAULT_FLASH_HZ(FAULT_FLASH_HZ)
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

    // Clock period = 10 ns
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Check traffic light outputs
    task automatic check_lights(
        input logic [2:0] n,
        input logic [2:0] e,
        input logic [2:0] s,
        input logic [2:0] w,
        input string test_name
    );
        begin
            if ({light_N, light_E, light_S, light_W} !==
                {n, e, s, w}) begin
                $display(
                    "FAIL: %s | N=%b E=%b S=%b W=%b",
                    test_name, light_N, light_E,
                    light_S, light_W
                );
                errors = errors + 1;
            end
            else begin
                $display("PASS: %s", test_name);
            end
        end
    endtask

    // Wait for a specific combination of traffic lights
    task automatic wait_for_lights(
        input logic [2:0] n,
        input logic [2:0] e,
        input logic [2:0] s,
        input logic [2:0] w
    );
        integer cycles;
        begin
            cycles = 0;

            while (({light_N, light_E, light_S, light_W} !==
                    {n, e, s, w}) && cycles < 100) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            if ({light_N, light_E, light_S, light_W} !==
                {n, e, s, w}) begin
                $display("FAIL: Timeout waiting for traffic lights");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst = 1'b1;
        emergency_vehicle = 1'b0;
        fault_detect = 1'b0;
        pedestrian_request = 4'b0000;

        $display("\n======================================");
        $display("  4-WAY TRAFFIC CONTROLLER TESTBENCH");
        $display("======================================");

        // TEST 1: Reset
        repeat (3) @(negedge clk);

        check_lights(
            RED, RED, RED, RED,
            "Reset: all approaches Red"
        );

        if (pedestrian_walk === 4'b0000)
            $display("PASS: Pedestrian outputs cleared on reset");
        else begin
            $display("FAIL: Pedestrian outputs during reset");
            errors = errors + 1;
        end

        rst = 1'b0;

        // TEST 2: North Green
        wait_for_lights(GREEN, RED, RED, RED);
        check_lights(
            GREEN, RED, RED, RED,
            "North Green"
        );

        // TEST 3: North Yellow
        wait_for_lights(YELLOW, RED, RED, RED);
        check_lights(
            YELLOW, RED, RED, RED,
            "North Yellow"
        );

        // TEST 4: All Red between approaches
        wait_for_lights(RED, RED, RED, RED);
        check_lights(
            RED, RED, RED, RED,
            "All Red after North"
        );

        // TEST 5: East Green
        wait_for_lights(RED, GREEN, RED, RED);
        check_lights(
            RED, GREEN, RED, RED,
            "East Green"
        );

        // TEST 6: Pedestrian request
        // The design serves pedestrian requests during All Red.
        wait_for_lights(RED, RED, RED, RED);

        @(negedge clk);
        pedestrian_request = 4'b0010;
        @(negedge clk);
        #1;

        if (pedestrian_walk === 4'b0010)
            $display("PASS: East pedestrian request served");
        else begin
            $display(
                "FAIL: East pedestrian request | walk=%b",
                pedestrian_walk
            );
            errors = errors + 1;
        end

        pedestrian_request = 4'b0000;

        // TEST 7: Emergency vehicle
        emergency_vehicle = 1'b1;

        // Wait for the two-stage input synchronizer
        repeat (4) @(negedge clk);
        #1;

        check_lights(
            RED, RED, RED, RED,
            "Emergency: all approaches Red"
        );

        if (pedestrian_walk === 4'b0000)
            $display("PASS: Pedestrian crossing disabled in emergency");
        else begin
            $display("FAIL: Pedestrian walk active in emergency");
            errors = errors + 1;
        end

        emergency_vehicle = 1'b0;
        repeat (4) @(negedge clk);

        // TEST 8: Fault detection
        fault_detect = 1'b1;

        // Allow fault synchronizer to respond
        repeat (4) @(negedge clk);
        #1;

        if (pedestrian_walk === 4'b0000)
            $display("PASS: Pedestrians stopped during fault");
        else begin
            $display("FAIL: Pedestrian output during fault");
            errors = errors + 1;
        end

        // TEST 9: Fault red flashing
        begin : fault_flash_test
            logic [2:0] previous_light;
            logic changed;
            integer i;

            previous_light = light_N;
            changed = 1'b0;

            for (i = 0; i < 30; i = i + 1) begin
                @(negedge clk);

                if (light_N !== previous_light)
                    changed = 1'b1;

                previous_light = light_N;
            end

            if (changed)
                $display("PASS: Fault red light flashes");
            else begin
                $display("FAIL: Fault red light did not flash");
                errors = errors + 1;
            end
        end

        // TEST 10: Fault priority and all-red recovery
        fault_detect = 1'b0;

        repeat (5) @(negedge clk);
        #1;

        check_lights(
            RED, RED, RED, RED,
            "All Red after fault recovery"
        );

        // TEST 11: No conflicting green lights
        repeat (30) begin
            @(negedge clk);

            if ((light_N[0] + light_E[0] +
                 light_S[0] + light_W[0]) > 1) begin
                $display("FAIL: Multiple green lights detected");
                errors = errors + 1;
            end
        end

        // Final result
        $display("\n======================================");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d error(s)", errors);
        $display("======================================\n");

        $finish;
    end

    // Simulation timeout
    initial begin
        #10000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
