`timescale 1ns/1ps

module testbench;

    // Short simulation timings
    localparam CLK_FREQ_HZ      = 10;
    localparam GREEN_TIME_SEC   = 2;
    localparam YELLOW_TIME_SEC  = 1;
    localparam ALL_RED_TIME_SEC = 1;

    logic clk;
    logic rst;
    logic emergency_vehicle;
    logic [1:0] emergency_approach;
    logic fault_detect;
    logic [3:0] pedestrian_request;

    logic [2:0] light_N;
    logic [2:0] light_E;
    logic [2:0] light_S;
    logic [2:0] light_W;
    logic [3:0] pedestrian_walk;
    logic [3:0] current_state;

    // State encodings from the DUT
    localparam N_GREEN    = 4'd0;
    localparam N_YELLOW   = 4'd1;
    localparam E_GREEN    = 4'd2;
    localparam E_YELLOW   = 4'd3;
    localparam S_GREEN    = 4'd4;
    localparam S_YELLOW   = 4'd5;
    localparam W_GREEN    = 4'd6;
    localparam W_YELLOW   = 4'd7;
    localparam ALL_RED    = 4'd8;
    localparam FAULT_FLASH = 4'd9;

    integer errors = 0;
    integer checks = 0;

    // Clock: 10 ns period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // DUT
    traffic_controller_4way #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .GREEN_TIME_SEC(GREEN_TIME_SEC),
        .YELLOW_TIME_SEC(YELLOW_TIME_SEC),
        .ALL_RED_TIME_SEC(ALL_RED_TIME_SEC)
    ) dut (
        .clk(clk),
        .rst(rst),
        .emergency_vehicle(emergency_vehicle),
        .emergency_approach(emergency_approach),
        .fault_detect(fault_detect),
        .pedestrian_request(pedestrian_request),
        .light_N(light_N),
        .light_E(light_E),
        .light_S(light_S),
        .light_W(light_W),
        .pedestrian_walk(pedestrian_walk),
        .current_state(current_state)
    );

    // Wait for a particular state, with a timeout.
    task automatic wait_for_state(
        input logic [3:0] expected_state,
        input integer max_cycles
    );
        integer i;
        bit found;
        begin
            found = 1'b0;

            for (i = 0; i < max_cycles; i = i + 1) begin
                @(negedge clk);
                if (current_state === expected_state) begin
                    found = 1'b1;
                    i = max_cycles;
                end
            end

            checks = checks + 1;
            if (found) begin
                $display(
                    "PASS: reached state %0d at time %0t",
                    expected_state, $time
                );
            end else begin
                errors = errors + 1;
                $error(
                    "FAIL: expected state %0d, got %0d at time %0t",
                    expected_state, current_state, $time
                );
            end
        end
    endtask

    // Verify all approaches are red.
    task automatic check_all_red;
        begin
            checks = checks + 1;
            if ((light_N !== 3'b100) ||
                (light_E !== 3'b100) ||
                (light_S !== 3'b100) ||
                (light_W !== 3'b100)) begin
                errors = errors + 1;
                $error("FAIL: all-red output check at time %0t", $time);
            end else begin
                $display("PASS: all approaches are red");
            end
        end
    endtask

    // Check that at most one approach has a green light.
    task automatic check_no_conflicting_greens;
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
                $error(
                    "FAIL: conflicting green lights at time %0t",
                    $time
                );
            end
        end
    endtask

    // Continuously check traffic-light safety after each rising edge.
    always @(posedge clk) begin
        #1;
        if (rst !== 1'b1) begin
            check_no_conflicting_greens();
        end
    end

    // Main stimulus
    initial begin
        $dumpfile("traffic_controller.vcd");
        $dumpvars(0, testbench);

        rst                 = 1'b1;
        emergency_vehicle   = 1'b0;
        emergency_approach  = 2'b00;
        fault_detect        = 1'b0;
        pedestrian_request  = 4'b0000;

        $display("\n===== TRAFFIC CONTROLLER TEST START =====");

        // 1. Reset test
        repeat (3) @(negedge clk);
        #1;
        check_all_red();

        if (current_state !== ALL_RED) begin
            errors = errors + 1;
            $error("FAIL: reset state should be ALL_RED");
        end else begin
            checks = checks + 1;
            $display("PASS: reset state is ALL_RED");
        end

        rst = 1'b0;

        // 2. Normal startup: All Red -> North Green
        wait_for_state(N_GREEN, 20);

        checks = checks + 1;
        if (light_N !== 3'b001) begin
            errors = errors + 1;
            $error("FAIL: North should be green");
        end else begin
            $display("PASS: North green output");
        end

        // 3. North Green -> North Yellow
        wait_for_state(N_YELLOW, 30);

        checks = checks + 1;
        if (light_N !== 3'b010) begin
            errors = errors + 1;
            $error("FAIL: North should be yellow");
        end else begin
            $display("PASS: North yellow output");
        end

        // 4. North Yellow -> All Red -> East Green
        wait_for_state(ALL_RED, 20);
        check_all_red();
        wait_for_state(E_GREEN, 20);

        checks = checks + 1;
        if (light_E !== 3'b001) begin
            errors = errors + 1;
            $error("FAIL: East should be green");
        end else begin
            $display("PASS: East green output");
        end

        // 5. Emergency request for South
        // The emergency is latched on its rising edge.
        @(negedge clk);
        emergency_approach = 2'b10;
        emergency_vehicle  = 1'b1;

        wait_for_state(ALL_RED, 10);
        check_all_red();

        @(negedge clk);
        emergency_vehicle = 1'b0;

        // All-red clearance occurs before South is served.
        wait_for_state(S_GREEN, 25);

        checks = checks + 1;
        if (light_S !== 3'b001) begin
            errors = errors + 1;
            $error("FAIL: emergency approach South should be green");
        end else begin
            $display("PASS: emergency request served for South");
        end

        // 6. Fault detection
        @(negedge clk);
        fault_detect = 1'b1;

        wait_for_state(FAULT_FLASH, 5);

        // No green may remain active in fault mode.
        checks = checks + 1;
        if (light_N[0] || light_E[0] ||
            light_S[0] || light_W[0]) begin
            errors = errors + 1;
            $error("FAIL: green output active during fault");
        end else begin
            $display("PASS: no green outputs during fault");
        end

        // Hold fault long enough for flash timer activity.
        repeat (12) @(negedge clk);
        fault_detect = 1'b0;

        // Fault recovery must pass through All Red.
        wait_for_state(ALL_RED, 10);
        check_all_red();

        // 7. Pedestrian request interface sanity check.
        // The design asserts walk only for the corresponding
        // request while that approach is green.
        pedestrian_request = 4'b0001;
        wait_for_state(N_GREEN, 30);
        #1;

        checks = checks + 1;
        if (pedestrian_walk[0] !== pedestrian_request[0]) begin
            errors = errors + 1;
            $error(
                "FAIL: North pedestrian output does not match request"
            );
        end else begin
            $display("PASS: North pedestrian output follows request");
        end

        // Finish
        repeat (3) @(negedge clk);

        $display("\n===== TEST SUMMARY =====");
        $display("Checks performed: %0d", checks);
        $display("Errors detected : %0d", errors);

        if (errors == 0)
            $display("OVERALL RESULT: PASS");
        else
            $display("OVERALL RESULT: FAIL");

        $finish;
    end

    // Global timeout protects against a stuck FSM.
    initial begin
        #100000;
        $fatal(1, "TIMEOUT: simulation did not finish");
    end

endmodule
