module adder_param #(
    parameter WIDTH = 16
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic             cin,
    output logic [WIDTH-1:0] sum,
    output logic             cout,
    output logic             overflow
);

    assign {cout, sum} = a + b + cin;

    // Signed overflow occurs when:
    // 1. Two positive numbers produce a negative result
    // 2. Two negative numbers produce a positive result
    assign overflow = (~(a[WIDTH-1] ^ b[WIDTH-1])) &
                      (sum[WIDTH-1] ^ a[WIDTH-1]);

endmodule
