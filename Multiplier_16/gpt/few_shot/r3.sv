`timescale 1ns/1ps

module multiplier16 (
    input  logic        clk,
    input  logic        rst,
    input  logic [15:0] a,
    input  logic [15:0] b,
    input  logic        signed_mode,
    input  logic        start,

    output logic [31:0] product,
    output logic        valid,
    output logic        overflow
);

    logic signed [31:0] signed_product;
    logic        [31:0] unsigned_product;
    logic        [31:0] selected_product;

    // ------------------------------------------------------------
    // Combinational multiplication
    // ------------------------------------------------------------
    always_comb begin

        signed_product   = $signed(a) * $signed(b);
        unsigned_product = $unsigned(a) * $unsigned(b);

        if (signed_mode)
            selected_product = signed_product;
        else
            selected_product = unsigned_product;

    end

    // ------------------------------------------------------------
    // Registered outputs
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin

        if (rst) begin
            product  <= 32'b0;
            valid    <= 1'b0;
            overflow <= 1'b0;
        end
        else begin

            // valid is a one-clock pulse
            valid <= 1'b0;

            if (start) begin

                // Full 32-bit result
                product <= selected_product;

                // ------------------------------------------------
                // Overflow detection
                // Overflow is defined relative to 16-bit output
                // representation.
                // ------------------------------------------------

                if (signed_mode) begin

                    // Signed 16-bit range:
                    // -32768 to +32767
                    //
                    // Upper bits must be equal to the sign bit.
                    overflow <=
                        (selected_product[31:16] !=
                         {16{selected_product[15]}});

                end
                else begin

                    // Unsigned 16-bit range:
                    // 0 to 65535
                    //
                    // Upper bits must be zero.
                    overflow <=
                        (selected_product[31:16] != 16'b0);

                end

                valid <= 1'b1;
            end
        end
    end

endmodule
