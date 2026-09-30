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

    logic signed [15:0] a_s;
    logic signed [15:0] b_s;

    logic signed [31:0] signed_result;
    logic        [31:0] unsigned_result;
    logic        [31:0] selected_result;

    // ------------------------------------------------------------
    // Combinational multiplication
    // ------------------------------------------------------------
    always_comb begin
        // Interpret the input bit patterns as signed two's-complement
        a_s = $signed(a);
        b_s = $signed(b);

        // Signed multiplication
        signed_result = a_s * b_s;

        // Unsigned multiplication
        unsigned_result = a * b;

        // Select the required result
        if (signed_mode)
            selected_result = signed_result;
        else
            selected_result = unsigned_result;
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
            // Default: valid is a one-cycle pulse
            valid <= 1'b0;

            if (start) begin
                // Full 32-bit product is always preserved
                product <= selected_result;

                if (signed_mode) begin
                    // ------------------------------------------------
                    // Signed overflow
                    //
                    // A signed 16-bit number has range:
                    // -32768 to +32767
                    //
                    // For a value to fit in 16 signed bits, bits
                    // [31:16] must be a sign extension of bit 15.
                    // ------------------------------------------------
                    if (selected_result[31:16] !=
                        {16{selected_result[15]}})
                        overflow <= 1'b1;
                    else
                        overflow <= 1'b0;
                end
                else begin
                    // ------------------------------------------------
                    // Unsigned overflow
                    //
                    // An unsigned 16-bit number has range:
                    // 0 to 65535
                    //
                    // Therefore upper 16 bits must be zero.
                    // ------------------------------------------------
                    if (selected_result[31:16] != 16'b0)
                        overflow <= 1'b1;
                    else
                        overflow <= 1'b0;
                end

                // Result is valid
                valid <= 1'b1;
            end
        end
    end

endmodule
