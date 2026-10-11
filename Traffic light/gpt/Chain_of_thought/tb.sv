`timescale 1ns/1ps

module testbench;

    // Use short timings to make simulation faster
    localparam CLK_FREQ_HZ      = 10;
    localparam GREEN_TIME_SEC   = 3;
    localparam YELLOW_TIME_SEC  = 2;
    localparam ALL_RED_TIME_SEC = 1;

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
    wire [3:0] state_display;

    // State encodings from the design
    localparam N_GREEN     = 4'd0;
    localparam N_YELLOW    = 4'd1;
    localparam E_GREEN     = 4'd2;
    localparam E_YELLOW    = 4'd3;
    localparam S_GREEN     = 4'd4;
    localparam S_YELLOW    = 4'd5;
    localparam W_GREEN     = 4'd6;
    localparam W_YELLOW    = 4'd7;
    localparam ALL_RED     = 4'd8;
    localparam FAULT_FLASH  = 4'd9;

    integer errors;

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
        .pedestrian_walk(pedestrian_walk),
        .state_display(state_display)
    );

    // 100 MHz simulation clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_state(
        input logic [3:0] expected,
        input string test_name
    );
        begin
            if (state_display !== expected) begin
                $display(
                    "FAIL: %s | Expected state=%0d, Got=%0d",
                    test_name, expected, state_display
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS: %s | State=%0d",
                    test_name, state_display
                );
            end
        end
    endtask

    task automatic wait_for_state(input logic [3:0] target);
        integer cycles;
        begin
            cycles = 0;
            while ((state_display !== target) && (cycles < 100)) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (state_display !== target) begin
                $display("FAIL: Timed out waiting for state %0d", target);
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

        $display("==================================");
        $display("  4-WAY TRAFFIC CONTROLLER TEST");
        $display("==================================");

        // Test 1: Reset
        repeat (2) @(negedge clk);
        check_state(ALL_RED, "Reset enters All Red");

        rst = 1'b0;

        // Test 2: Normal traffic sequence
        wait_for_state(N_GREEN);
        check_state(N_GREEN, "North Green");

        wait_for_state(N_YELLOW);
        check_state(N_YELLOW, "North Yellow");

        wait_for_state(ALL_RED);
        check_state(ALL_RED, "All Red after North");

        wait_for_state(E_GREEN);
        check_state(E_GREEN, "East Green");

        // Test 3: Pedestrian request for East
        pedestrian_request = 4'b0010;
        #1;
        if (pedestrian_walk[1] !== 1'b1) begin
            $display("FAIL: East pedestrian walk not enabled");
            errors = errors + 1;
        end
        else begin
            $display("PASS: East pedestrian walk enabled");
        end

        // Pedestrian walk must be disabled during emergency
        emergency_vehicle = 1'b1;
        #1;
        if (pedestrian_walk !== 4'b0000) begin
            $display("FAIL: Pedestrian walk active during emergency");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Pedestrian walk disabled during emergency");
        end

        // All approaches must show red during emergency
        if ({light_N, light_E, light_S, light_W} !==
            {3'b100, 3'b100, 3'b100, 3'b100}) begin
            $display("FAIL: All-red lights not set during emergency");
            errors = errors + 1;
        end
        else begin
            $display("PASS: All directions red during emergency");
        end

        emergency_vehicle = 1'b0;
        pedestrian_request = 4'b0000;

        // The design resumes its scheduled sequence.
        // Wait for East Green, which was interrupted by the emergency.
        wait_for_state(E_GREEN);
        check_state(E_GREEN, "Resumes East Green");

        // Test 4: Fault mode
        @(negedge clk);
        fault_detect = 1'b1;
        #1;
        check_state(FAULT_FLASH, "Fault enters flashing state");

        if (pedestrian_walk !== 4'b0000) begin
            $display("FAIL: Pedestrian walk active during fault");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Pedestrian walk disabled during fault");
        end

        // Confirm flashing output changes within several clock cycles
        begin : flash_test
            logic [2:0] saved_light;
            integer i;
            logic changed;

            saved_light = light_N;
            changed = 1'b0;

            for (i = 0; i < 15; i = i + 1) begin
                @(negedge clk);
                if (light_N !== saved_light)
                    changed = 1'b1;
            end

            if (changed) begin
                $display("PASS: Fault light flashes");
            end
            else begin
                $display("FAIL: Fault light did not flash");
                errors = errors + 1;
            end
        end

        // Clear fault; the controller should return to All Red
        fault_detect = 1'b0;
        wait_for_state(ALL_RED);
        check_state(ALL_RED, "Returns to All Red after fault");

        // Test 5: Check the remaining traffic directions
        wait_for_state(S_GREEN);
        check_state(S_GREEN, "South Green");

        wait_for_state(S_YELLOW);
        check_state(S_YELLOW, "South Yellow");

        wait_for_state(ALL_RED);
        check_state(ALL_RED, "All Red after South");

        wait_for_state(W_GREEN);
        check_state(W_GREEN, "West Green");

        $display("----------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d error(s)", errors);
        $display("----------------------------------");

        $finish;
    end

    initial begin
        #10000;
        $display("FAIL: Global simulation timeout");
        $finish;
    end

endmodule
