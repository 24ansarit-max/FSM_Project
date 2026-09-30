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
    // 1. INPUT REGISTRATION
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
    // 2. SIGN / ZERO EXTENSION
    // ============================================================
    logic signed [16:0] A_ext;
    logic signed [16:0] B_ext;

    always_comb begin
        // Default assignments prevent latch inference.
        A_ext = 17'sd0;
        B_ext = 17'sd0;

        if (signed_mode_reg) begin
            // Signed 16-bit -> signed 17-bit
            A_ext = $signed({A_reg[15], A_reg});
            B_ext = $signed({B_reg[15], B_reg});
        end
        else begin
            // Unsigned 16-bit -> zero-extended 17-bit
            A_ext = $signed({1'b0, $unsigned(A_reg)});
            B_ext = $signed({1'b0, $unsigned(B_reg)});
        end
    end

    // ============================================================
    // 3. SINGLE SHARED MULTIPLIER DATAPATH
    // ============================================================
    logic signed [33:0] mult_result;

    always_comb begin
        // 17 x 17 = 34 bits
        mult_result = 34'sd0;
        mult_result = $signed(A_ext) * $signed(B_ext);
    end

    // Required 32-bit product.
    logic [31:0] product_comb;

    always_comb begin
        product_comb = 32'b0;
        product_comb = mult_result[31:0];
    end

    // ============================================================
    // 4. REGISTERED OUTPUT / OVERFLOW LOGIC
    // ============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            product   <= 32'b0;
            overflow  <= 1'b0;
            valid_out <= 1'b0;
        end
        else begin
            // Default: valid is a one-cycle pulse.
            valid_out <= 1'b0;

            if (start_reg) begin
                product <= product_comb;

                if (signed_mode_reg) begin
                    // Signed 16-bit result must be in:
                    // -32768 to +32767
                    //
                    // Upper 16 bits must equal the sign
                    // extension of bit 15.
                    overflow <=
                        (product_comb[31:16] !=
                         {16{product_comb[15]}});
                end
                else begin
                    // Unsigned 16-bit result must be in:
                    // 0 to 65535
                    //
                    // Upper 16 bits must be zero.
                    overflow <=
                        (product_comb[31:16] != 16'b0);
                end

                valid_out <= 1'b1;
            end
        end
    end

endmodule
