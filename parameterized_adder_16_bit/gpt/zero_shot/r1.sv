module parameterized_adder #(
    parameter int WIDTH = 16
)(
    input  logic [WIDTH-1:0] A,
    input  logic [WIDTH-1:0] B,
    input  logic             Cin,
    output logic [WIDTH-1:0] Sum,
    output logic             Cout
);

    assign {Cout, Sum} = A + B + Cin;

endmodule
