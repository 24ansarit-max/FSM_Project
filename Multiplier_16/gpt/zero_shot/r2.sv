`timescale 1ns/1ps

module multiplier_16bit (
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

    // ------------------------------------------------------------
    // Internal signals
    // ------------------------------------------------------------

    logic signed [15:0] a_signed;
    logic signed [15:0] b_signed;

    logic signed [31:0] signed_product;
    logic        [31:0] unsigned_product;

    logic [31:0] selected_product;

    // ------------------------------------------------------------
    // Combinational multiplier
    // ------------------------------------------------------------

    always_comb begin

        // Explicitly interpret the 16-bit bit patterns as
        // two's-complement signed values.
        a_signed = $signed(a);
        b_signed = $signed(b);

        // Signed multiplication
        signed_product = a_signed * b_signed;

        // Unsigned multiplication
        unsigned_product = a * b;

        // Select according to operating mode
        if (signed_mode)
            selected_product = signed_product;
        else
            selected_product = unsigned_product;

    end

    // ------------------------------------------------------------
    // Sequential output logic
    // ------------------------------------------------------------

    always_ff @(posedge clk) begin

        if (rst) begin
            product  <= 32'b0;
            valid    <= 1'b0;
            overflow <= 1'b0;
        end
        else begin

            // valid is normally LOW
            valid <= 1'b0;

            if (start) begin

                // Preserve complete 32-bit result
                product <= selected_product;

                // ------------------------------------------------
                // Overflow detection
                // ------------------------------------------------

                if (signed_mode) begin

                    // Signed 16-bit range:
                    // -32768 to +32767
                    //
                    // A valid signed 16-bit result must have
                    // upper 16 bits equal to the sign extension
                    // of bit 15.

                    if (selected_product[31:16] !=
                        {16{selected_product[15]}})
                        overflow <= 1'b1;
                    else
                        overflow <= 1'b0;

                end
                else begin

                    // Unsigned 16-bit range:
                    // 0 to 65535
                    //
                    // Upper 16 bits must be zero.

                    if (selected_product[31:16] != 16'b0)
                        overflow <= 1'b1;
                    else
                        overflow <= 1'b0;

                end

                // Result is now available
                valid <= 1'b1;

            end
        end
    end

endmodule
