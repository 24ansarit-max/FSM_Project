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
    // 1. Registered inputs
    // ============================================================
    logic [15:0] A_reg;
    logic [15:0] B_reg;
    logic        signed_mode_reg;
    logic        start_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            A_reg           <= 16'b0;
            B_reg           <= 16'b0;
            signed_mode_reg <= 1'b0;
            start_reg       <= 1'b0;
        end
        else begin
            A_reg           <= A;
            B_reg           <= B;
            signed_mode_reg <= signed_mode;
            start_reg       <= start;
        end
    end

    // ============================================================
    // 2. Mode-dependent 17-bit extension
    //
    // Signed:
    //   A[15] = 1 -> 17'b1_A[15:0]
    //   A[15] = 0 -> 17'b0_A[15:0]
    //
    // Unsigned:
    //   Always zero extend.
    //
    // The leading zero in unsigned mode guarantees that the
    // 17-bit operands are positive even though they are passed
    // to the shared signed multiplier.
    // ============================================================
    logic signed [16:0] A_ext;
    logic signed [16:0] B_ext;

    always_comb begin
        A_ext = 17'sd0;
        B_ext = 17'sd0;

        if (signed_mode_reg) begin
            A_ext = $signed({A_reg[15], A_reg});
            B_ext = $signed({B_reg[15], B_reg});
        end
        else begin
            A_ext = $signed({1'b0, $unsigned(A_reg)});
            B_ext = $signed({1'b0, $unsigned(B_reg)});
        end
    end

    // ============================================================
    // 3. Single shared multiplier datapath
    // ============================================================
    logic signed [33:0] mult_result;

    always_comb begin
        mult_result = 34'sd0;
        mult_result = $signed(A_ext) * $signed(B_ext);
    end

    // The required 32-bit product is the lower 32 bits.
    logic [31:0] product_comb;

    always_comb begin
        product_comb = 32'b0;
        product_comb = mult_result[31:0];
    end

    // ============================================================
    // 4. Registered product / overflow / valid
    //
    // Input registers:
    //     Cycle N
    //
    // Product registers:
    //     Cycle N+1
    //
    // Therefore valid_out is aligned with product.
    // ============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            product   <= 32'b0;
            overflow  <= 1'b0;
            valid_out <= 1'b0;
        end
        else begin
            valid_out <= 1'b0;

            if (start_reg) begin
                product <= product_comb;

                if (signed_mode_reg) begin
                    // Signed 16-bit range:
                    // -32768 to +32767
                    //
                    // No overflow when bits [31:16] are exactly
                    // the sign extension of bit [15].
                    overflow <=
                        (product_comb[31:16] !=
                         {16{product_comb[15]}});
                end
                else begin
                    // Unsigned 16-bit range:
                    // 0 to 65535
                    //
                    // No overflow when upper 16 bits are zero.
                    overflow <=
                        (product_comb[31:16] != 16'b0);
                end

                valid_out <= 1'b1;
            end
        end
    end

endmodule
