module parameterized_adder #(
    parameter int unsigned WIDTH = 16
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic             cin,

    output logic [WIDTH-1:0] sum,
    output logic             cout,
    output logic             overflow
);

    logic [WIDTH:0] extended_sum;

    initial begin
        if (WIDTH < 1) begin
            $error("WIDTH must be greater than or equal to 1");
        end
    end

    assign extended_sum =
        {1'b0, a} +
        {1'b0, b} +
        {{WIDTH{1'b0}}, cin};

    assign sum  = extended_sum[WIDTH-1:0];
    assign cout = extended_sum[WIDTH];

    // Two's-complement signed overflow:
    // operands have the same sign, but result has a different sign.
    assign overflow =
        ~(a[WIDTH-1] ^ b[WIDTH-1]) &
         (sum[WIDTH-1] ^ a[WIDTH-1]);

endmodule
