module parameterized_adder #(
    parameter int WIDTH = 16
)(
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic             cin,
    output logic [WIDTH-1:0] sum,
    output logic             cout,
    output logic             overflow
);

    logic [WIDTH:0] result;

    // WIDTH+1-bit unsigned addition
    assign result = {1'b0, a} +
                    {1'b0, b} +
                    {{WIDTH{1'b0}}, cin};

    // Lower WIDTH bits
    assign sum = result[WIDTH-1:0];

    // Most-significant carry bit
    assign cout = result[WIDTH];

    // Signed two's-complement overflow detection
    assign overflow = (~(a[WIDTH-1] ^ b[WIDTH-1])) &
                       (sum[WIDTH-1] ^ a[WIDTH-1]);

endmodule
