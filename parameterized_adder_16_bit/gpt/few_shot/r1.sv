module adder_param #(
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

    assign result = {1'b0, a} + {1'b0, b} + cin;

    assign sum  = result[WIDTH-1:0];
    assign cout = result[WIDTH];

    // Signed overflow:
    // Positive + Positive = Negative
    // Negative + Negative = Positive
    assign overflow = (~(a[WIDTH-1] ^ b[WIDTH-1])) &
                      (sum[WIDTH-1] ^ a[WIDTH-1]);

endmodule
