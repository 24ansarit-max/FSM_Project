`timescale 1ns/1ps

module parameterized_mac_tb;

parameter DATA_WIDTH = 8;
parameter ACC_WIDTH  = 32;

reg clk;
reg rst;
reg start;
reg clear_acc;

reg [DATA_WIDTH-1:0] A;
reg [DATA_WIDTH-1:0] B;

reg signed_mode;
reg valid_in;
reg last;

wire [ACC_WIDTH-1:0] acc_out;
wire valid_out;
wire done;
wire busy;
wire overflow;
wire saturated;


// ============================================================
// DUT
// ============================================================

parameterized_mac #(
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) dut (
    .clk(clk),
    .rst(rst),
    .start(start),
    .clear_acc(clear_acc),
    .A(A),
    .B(B),
    .signed_mode(signed_mode),
    .valid_in(valid_in),
    .last(last),
    .acc_out(acc_out),
    .valid_out(valid_out),
    .done(done),
    .busy(busy),
    .overflow(overflow),
    .saturated(saturated)
);


// ============================================================
// CLOCK
// ============================================================

initial begin
    clk = 0;

    forever begin
        #5 clk = ~clk;
    end
end


// ============================================================
// TASK: START MAC
// ============================================================

task start_mac;
input mode;
begin

    @(negedge clk);

    signed_mode = mode;
    start = 1;

    @(negedge clk);

    start = 0;

    wait(dut.state == dut.LOAD);

end
endtask


// ============================================================
// TASK: SEND DATA
// ============================================================

task send_data;
input [DATA_WIDTH-1:0] data_a;
input [DATA_WIDTH-1:0] data_b;
input last_value;

begin

    wait(dut.state == dut.LOAD);

    @(negedge clk);

    A = data_a;
    B = data_b;
    last = last_value;
    valid_in = 1;

    @(negedge clk);

    valid_in = 0;
    last = 0;

    A = 0;
    B = 0;

end
endtask


// ============================================================
// TASK: WAIT FOR DONE
// ============================================================

task wait_done;
begin

    wait(done == 1);

    @(negedge clk);

end
endtask


// ============================================================
// MAIN TEST
// ============================================================

initial begin

    // Initial values

    rst = 1;
    start = 0;
    clear_acc = 0;

    A = 0;
    B = 0;

    signed_mode = 0;
    valid_in = 0;
    last = 0;


    $display("");
    $display("========================================");
    $display("       PARAMETERIZED MAC TEST");
    $display("========================================");


    // --------------------------------------------------------
    // RESET
    // --------------------------------------------------------

    repeat(3) @(negedge clk);

    rst = 0;


    // ========================================================
    // TEST 1
    // 3*4 + 5*6 = 42
    // ========================================================

    $display("");
    $display("TEST 1 : UNSIGNED MAC");

    start_mac(0);

    send_data(8'd3,8'd4,0);

    send_data(8'd5,8'd6,1);

    wait_done;

    if(acc_out == 32'd42)
        $display("PASS : Expected 42, Got %0d",acc_out);
    else
        $display("FAIL : Expected 42, Got %0d",acc_out);


    // ========================================================
    // TEST 2
    // 10*20 = 200
    // ========================================================

    $display("");
    $display("TEST 2 : SINGLE MULTIPLICATION");

    start_mac(0);

    send_data(8'd10,8'd20,1);

    wait_done;

    if(acc_out == 32'd200)
        $display("PASS : Expected 200, Got %0d",acc_out);
    else
        $display("FAIL : Expected 200, Got %0d",acc_out);


    // ========================================================
    // TEST 3
    // 100*2 + 20*3 + 5*4 = 280
    // ========================================================

    $display("");
    $display("TEST 3 : MULTIPLE MAC");

    start_mac(0);

    send_data(8'd100,8'd2,0);

    send_data(8'd20,8'd3,0);

    send_data(8'd5,8'd4,1);

    wait_done;

    if(acc_out == 32'd280)
        $display("PASS : Expected 280, Got %0d",acc_out);
    else
        $display("FAIL : Expected 280, Got %0d",acc_out);


    // ========================================================
    // TEST 4
    // (-5)*4 + 3*2 = -14
    // ========================================================

    $display("");
    $display("TEST 4 : SIGNED MAC");

    start_mac(1);

    send_data(8'hFB,8'd4,0);

    send_data(8'd3,8'd2,1);

    wait_done;

    if($signed(acc_out) == -14)
        $display("PASS : Expected -14, Got %0d",
                 $signed(acc_out));
    else
        $display("FAIL : Expected -14, Got %0d",
                 $signed(acc_out));


    // ========================================================
    // TEST 5
    // VALID_IN = 0
    // FSM should remain in LOAD
    // ========================================================

    $display("");
    $display("TEST 5 : VALID_IN DROP");

    start_mac(0);

    repeat(4) @(negedge clk);

    if(dut.state == dut.LOAD)
        $display("PASS : FSM waiting in LOAD");
    else
        $display("FAIL : FSM left LOAD");


    send_data(8'd7,8'd8,1);

    wait_done;

    if(acc_out == 32'd56)
        $display("PASS : Expected 56, Got %0d",acc_out);
    else
        $display("FAIL : Expected 56, Got %0d",acc_out);


    // ========================================================
    // TEST 6
    // CLEAR ACCUMULATOR
    // ========================================================

    $display("");
    $display("TEST 6 : CLEAR ACCUMULATOR");

    start_mac(0);

    send_data(8'd10,8'd10,0);

    wait(dut.state == dut.LOAD);

    @(negedge clk);

    clear_acc = 1;

    @(negedge clk);

    clear_acc = 0;

    send_data(8'd2,8'd3,1);

    wait_done;

    if(acc_out == 32'd6)
        $display("PASS : Expected 6, Got %0d",acc_out);
    else
        $display("FAIL : Expected 6, Got %0d",acc_out);


    // ========================================================
    // TEST 7
    // START WHILE BUSY
    //
    // Expected:
    // 4*5 + 2*3 = 26
    // ========================================================

    $display("");
    $display("TEST 7 : START WHILE BUSY");

    start_mac(0);

    send_data(8'd4,8'd5,0);

    wait(dut.state == dut.LOAD);

    @(negedge clk);

    start = 1;

    @(negedge clk);

    start = 0;

    send_data(8'd2,8'd3,1);

    wait_done;

    if(acc_out == 32'd26)
        $display("PASS : Expected 26, Got %0d",acc_out);
    else
        $display("FAIL : Expected 26, Got %0d",acc_out);


    // ========================================================
    // FINISH
    // ========================================================

    $display("");
    $display("========================================");
    $display("        ALL MAC TESTS COMPLETED");
    $display("========================================");
    $display("");

    #20;

    $finish;

end


// ============================================================
// MONITOR
// ============================================================

initial begin

    $monitor(
        "T=%0t | STATE=%0d | rst=%b | start=%b | clear=%b | A=%0d | B=%0d | valid=%b | last=%b | acc=%0d | done=%b | busy=%b | overflow=%b | saturated=%b",
        $time,
        dut.state,
        rst,
        start,
        clear_acc,
        A,
        B,
        valid_in,
        last,
        acc_out,
        done,
        busy,
        overflow,
        saturated
    );

end

endmodule
