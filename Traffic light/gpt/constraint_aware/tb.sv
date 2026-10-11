
`timescale 1ns/1ps

module testbench;

    // Short timings for simulation
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

    wire [2:0] light_N, light_E, light_S, light_W;
    wire [3:0] pedestrian_walk;
    wire [3:0] state_display;

    localparam N_GREEN  = 4'd0;
    localparam N_YELLOW = 4'd1;
    localparam E_GREEN  = 4'd2;
    localparam E_YELLOW = 4'd3;
    localparam S_GREEN  = 4'd4;
    localparam S_YELLOW = 4'd5;
    localparam W_GREEN  = 4'd6;
    localparam W_YELLOW = 4'd7;
    localparam ALL_RED  = 4'd8;
    localparam FAULT     = 4'd9;

    integer errors;

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
        .pedestrian_walk(pedestrian_walk),
        .state_display(state_display)
    );

    // 10 ns clock period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_state(
        input logic [3:0] expected,
        input string test_name
    );
        begin
            if (state_display !== expected) begin
                $display(
                    "FAIL: %s expected=%0d actual=%0d",
                    test_name, expected, state_display
                );
                errors = errors + 1;
            end
            else begin
                $display("PASS: %s", test_name);
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
                $display("FAIL: Timeout waiting for state %0d", target);
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

        $display("\n===== TRAFFIC CONTROLLER TEST =====");

        // TEST 1: Reset
        repeat (3) @(negedge clk);
        check_state(ALL_RED, "Reset state is All Red");

        if ({light_N, light_E, light_S, light_W} ===
            {3'b100, 3'b100, 3'b100, 3'b100})
            $display("PASS: All lights red during reset");
        else begin
            $display("FAIL: Reset light outputs");
            errors = errors + 1;
        end

        rst = 1'b0;

        // TEST 2: North traffic
        wait_for_state(N_GREEN);
        check_state(N_GREEN, "North Green");

        wait_for_state(N_YELLOW);
        check_state(N_YELLOW, "North Yellow");

        wait_for_state(ALL_RED);
        check_state(ALL_RED, "All Red after North");

        // TEST 3: East traffic
        wait_for_state(E_GREEN);
        check_state(E_GREEN, "East Green");

        // Request pedestrian crossing at East
        @(negedge clk);
        pedestrian_request = 4'b0010;
        @(negedge clk);

        if (pedestrian_walk[1] === 1'b1)
            $display("PASS: East pedestrian walk enabled");
        else begin
            $display("FAIL: East pedestrian walk not enabled");
            errors = errors + 1;
        end

        // TEST 4: Emergency vehicle
        emergency_vehicle = 1'b1;

        // Synchronizer needs clock edges
        repeat (4) @(negedge clk);
        check_state(ALL_RED, "Emergency enters All Red");

        if ({light_N, light_E, light_S, light_W} ===
            {3'b100, 3'b100, 3'b100, 3'b100})
            $display("PASS: All approaches red during emergency");
        else begin
            $display("FAIL: Emergency light outputs");
            errors = errors + 1;
        end

        if (pedestrian_walk === 4'b0000)
            $display("PASS: Pedestrians stopped during emergency");
        else begin
            $display("FAIL: Pedestrian output during emergency");
            errors = errors + 1;
        end

        emergency_vehicle = 1'b0;
        pedestrian_request = 4'b0000;

        // Allow synchronized input to clear and traffic to resume
        wait_for_state(E_GREEN);
        check_state(E_GREEN, "Traffic resumes at East");

        // TEST 5: Fault detection
        @(negedge clk);
        fault_detect = 1'b1;

        // Fault input passes through a two-stage synchronizer
        wait_for_state(FAULT);
        check_state(FAULT, "Fault state entered");

        if (pedestrian_walk === 4'b0000)
            $display("PASS: Pedestrian crossing disabled during fault");
        else begin
            $display("FAIL: Pedestrian crossing during fault");
            errors = errors + 1;
        end

        // Verify that the fault red output changes
        begin : flash_check
            logic [2:0] saved_light;
            logic changed;
            integer i;

            saved_light = light_N;
            changed = 1'b0;

            for (i = 0; i < 15; i = i + 1) begin
                @(negedge clk);
                if (light_N !== saved_light)
                    changed = 1'b1;
            end

            if (changed)
                $display("PASS: Fault red light flashes");
            else begin
                $display("FAIL: Fault red light did not flash");
                errors = errors + 1;
            end
        end

        // TEST 6: Clear fault and check recovery
        fault_detect = 1'b0;
        wait_for_state(ALL_RED);
        check_state(ALL_RED, "Recovery to All Red");

        // Synchronizer may take additional cycles to clear fault
        repeat (4) @(negedge clk);

        // Check South and West phases in the normal sequence
        wait_for_state(S_GREEN);
        check_state(S_GREEN, "South Green");

        wait_for_state(S_YELLOW);
        check_state(S_YELLOW, "South Yellow");

        wait_for_state(ALL_RED);
        check_state(ALL_RED, "All Red after South");

        wait_for_state(W_GREEN);
        check_state(W_GREEN, "West Green");

        // Final summary
        $display("\n==================================");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d errors", errors);
        $display("==================================\n");

        $finish;
    end

    // Global simulation timeout
    initial begin
        #10000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
