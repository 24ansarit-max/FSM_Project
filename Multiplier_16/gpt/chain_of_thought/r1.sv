```systemverilog
`timescale 1ns/1ps

module multiplier_16bit (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,

    input  logic [15:0] A,
    input  logic [15:0] B,
    input  logic        signed_mode,

    output logic [31:0] product,
    output logic        valid_out,
    output logic        overflow
);

    // ============================================================
    // Internal multiplication results
    // ============================================================

    logic signed [31:0] signed_product;
    logic        [31:0] unsigned_product;
    logic        [31:0] selected_product;

    // ============================================================
    // Combinational multiplication datapath
    // ============================================================

    always_comb begin

        // Signed two's-complement multiplication
        signed_product =
            $signed(A) * $signed(B);

        // Unsigned multiplication
        unsigned_product =
            $unsigned(A) * $unsigned(B);

        // Select result according to signed_mode
        if (signed_mode)
            selected_product = signed_product;
        else
            selected_product = unsigned_product;

    end

    // ============================================================
    // Registered output and overflow logic
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            product   <= 32'b0;
            valid_out <= 1'b0;
            overflow  <= 1'b0;

        end
        else begin

            // valid_out is a one-clock pulse
            valid_out <= 1'b0;

            if (start) begin

                // Store complete 32-bit multiplication result
                product <= selected_product;

                // ------------------------------------------------
                // Overflow detection
                // ------------------------------------------------

                if (signed_mode) begin

                    // Signed 16-bit range:
                    // -32768 to +32767
                    //
                    // The upper 16 bits must be the sign extension
                    // of bit 15.

                    overflow <=
                        (selected_product[31:16] !=
                         {16{selected_product[15]}});

                end
                else begin

                    // Unsigned 16-bit range:
                    // 0 to 65535
                    //
                    // Upper 16 bits must all be zero.

                    overflow <=
                        (selected_product[31:16] != 16'b0);

                end

                // Result is valid
                valid_out <= 1'b1;

            end

        end

    end

endmodule
```
