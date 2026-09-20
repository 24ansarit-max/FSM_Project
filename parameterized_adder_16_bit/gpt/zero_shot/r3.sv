module parameterized_adder #(
    parameter int WIDTH = 16
)(
    input  logic [WIDTH-1:0] A,
    input  logic [WIDTH-1:0] B,
    input  logic              Cin,
    output logic [WIDTH-1:0] Sum,
    output logic              Cout
);

    logic [WIDTH:0] result;

    assign result = {1'b0, A} + {1'b0, B} + Cin;

    assign Sum  = result[WIDTH-1:0];
    assign Cout = result[WIDTH];

endmodule
