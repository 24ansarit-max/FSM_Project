module parameterized_adder #(
    parameter int WIDTH = 16
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic             cin,

    output logic [WIDTH-1:0] sum,
    output logic             cout,
    output logic             overflow
);

    logic [WIDTH:0] result;

    // WIDTH+1 bit addition preserves carry-out
    assign result = {1'b0, a} + {1'b0, b} + cin;

    // Lower WIDTH bits are the sum
    assign sum = result[WIDTH-1:0];

    // Most significant bit is the unsigned carry-out
    assign cout = result[WIDTH];

    // Signed two's-complement overflow
    assign overflow =
        ~(a[WIDTH-1] ^ b[WIDTH-1]) &
         (sum[WIDTH-1] ^ a[WIDTH-1]);

endmodule
