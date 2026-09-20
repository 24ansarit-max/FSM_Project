module adder_param #(
  parameter WIDTH = 16
) (
  input  logic [WIDTH-1:0] a,
  input  logic [WIDTH-1:0] b,
  input  logic cin,
  output logic [WIDTH-1:0] sum,
  output logic cout,
  output logic overflow
);

  logic [WIDTH:0] result;

  assign result = a + b + cin;

  assign sum  = result[WIDTH-1:0];
  assign cout = result[WIDTH];

  // Signed overflow detection
  assign overflow = (~(a[WIDTH-1] ^ b[WIDTH-1])) &
                    (sum[WIDTH-1] ^ a[WIDTH-1]);

endmodule
