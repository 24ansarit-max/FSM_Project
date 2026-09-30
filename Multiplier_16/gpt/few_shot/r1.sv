```systemverilog
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

    logic [31:0] selected_product;

    // ------------------------------------------------------------
    // Multiplication
    // ------------------------------------------------------------
    always_comb begin

        // Signed multiplication
        signed_product = $signed(a) * $signed(b);

        // Unsigned multiplication
        unsigned_product = $unsigned(a) * $unsigned(b);

        // Select multiplication mode
        if (signed_mode)
            selected_product = signed_product;
        else
            selected_product = unsigned_product;

    end

    // ------------------------------------------------------------
    // Registered output and overflow detection
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

                // Store complete 32-bit product
                product <= selected_product;

                // ------------------------------------------------
                // Overflow detection
                //
                // Overflow is defined relative to a 16-bit result.
                // ------------------------------------------------

                if (signed_mode) begin

                    // Signed 16-bit result must have the upper
                    // 16 bits equal to the sign extension of bit 15.
                    //
                    // This is equivalent to checking whether the
                    // full product fits in the range:
                    // -32768 to +32767.

                    overflow <=
                        (selected_product[31:16] !=
                         {16{selected_product[15]}});

                end
                else begin

                    // Unsigned 16-bit result can only use bits [15:0].
                    // Any '1' in bits [31:16] indicates overflow.

                    overflow <=
                        (selected_product[31:16] != 16'b0);

                end

                valid <= 1'b1;

            end
        end
    end

endmodule
```
