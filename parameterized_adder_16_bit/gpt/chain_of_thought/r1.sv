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

    // Addition with an extra bit for carry-out
    assign result = {1'b0, a} + {1'b0, b} + cin;

    // Result and carry-out
    assign sum  = result[WIDTH-1:0];
    assign cout = result[WIDTH];

    // Signed two's-complement overflow detection
    assign overflow = ~(a[WIDTH-1] ^ b[WIDTH-1]) &
                      (sum[WIDTH-1] ^ a[WIDTH-1]);

endmodule
