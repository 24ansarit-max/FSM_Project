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

    // WIDTH+1 bit addition
    assign {cout, sum} = a + b + cin;

    // Signed two's-complement overflow detection
    assign overflow = ~(a[WIDTH-1] ^ b[WIDTH-1]) &
                      (sum[WIDTH-1] ^ a[WIDTH-1]);

endmodule
