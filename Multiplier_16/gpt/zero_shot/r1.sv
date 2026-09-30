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

    logic signed [15:0]  a_signed;
    logic signed [15:0]  b_signed;

    logic signed [31:0]  signed_result;
    logic        [31:0]  unsigned_result;

    logic [31:0] result;

    // ------------------------------------------------------------
    // Interpret operands and perform multiplication
    // ------------------------------------------------------------

    always_comb begin

        // Explicit signed interpretation.
        // The bit pattern itself is unchanged; $signed tells
        // SystemVerilog to interpret it as two's-complement.
        a_signed = $signed(a);
        b_signed = $signed(b);

        // Signed 16 x 16 -> 32 bit multiplication
        signed_result = a_signed * b_signed;

        // Unsigned 16 x 16 -> 32 bit multiplication
        unsigned_result = a * b;

        // Select result according to mode
        if (signed_mode)
            result = signed_result;
        else
            result = unsigned_result;

    end

    // ------------------------------------------------------------
    // Registered output
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

                // Store full 32-bit product
                product <= result;

                // ------------------------------------------------
                // Overflow detection
                // ------------------------------------------------

                if (signed_mode) begin

                    // Signed 16-bit range:
                    // -32768 to +32767
                    //
                    // If the upper 16 bits are not a proper
                    // sign extension of bit 15, overflow occurred.

                    if (result[31:16] != {16{result[15]}})
                        overflow <= 1'b1;
                    else
                        overflow <= 1'b0;

                end
                else begin

                    // Unsigned 16-bit range:
                    // 0 to 65535
                    //
                    // Any non-zero upper 16 bits means the
                    // result cannot fit in 16 unsigned bits.

                    if (result[31:16] != 16'b0)
                        overflow <= 1'b1;
                    else
                        overflow <= 1'b0;

                end

                // Result is ready
                valid <= 1'b1;

            end
        end
    end

endmodule
