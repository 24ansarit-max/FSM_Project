`timescale 1ns/1ps

module multiplier_signed_unsigned #(
    parameter int unsigned DATA_WIDTH = 16
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic [DATA_WIDTH-1:0]        A,
    input  logic [DATA_WIDTH-1:0]        B,
    input  logic                         signed_mode,
    input  logic                         start,

    output logic [(2*DATA_WIDTH)-1:0]    product,
    output logic                         valid_out,
    output logic                         overflow
);

    localparam int unsigned EXT_WIDTH  = DATA_WIDTH + 1;
    localparam int unsigned PROD_WIDTH = 2 * DATA_WIDTH;
    localparam int unsigned MULT_WIDTH = 2 * EXT_WIDTH;

    // ============================================================
    // 1. INPUT REGISTRATION
    // ============================================================
    logic [DATA_WIDTH-1:0] A_reg;
    logic [DATA_WIDTH-1:0] B_reg;
    logic                  signed_mode_reg;
    logic                  start_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            A_reg           <= '0;
            B_reg           <= '0;
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
    logic signed [EXT_WIDTH-1:0] A_ext;
    logic signed [EXT_WIDTH-1:0] B_ext;

    always_comb begin
        // Default assignments prevent latch inference.
        A_ext = '0;
        B_ext = '0;

        if (signed_mode_reg) begin
            // Signed:
            //   {sign bit, original operand}
            A_ext = $signed({A_reg[DATA_WIDTH-1], A_reg});
            B_ext = $signed({B_reg[DATA_WIDTH-1], B_reg});
        end
        else begin
            // Unsigned:
            //   explicit zero extension
            A_ext = $signed({1'b0, $unsigned(A_reg)});
            B_ext = $signed({1'b0, $unsigned(B_reg)});
        end
    end

    // ============================================================
    // 3. SINGLE SHARED MULTIPLIER DATAPATH
    // ============================================================
    logic signed [MULT_WIDTH-1:0] mult_result;

    always_comb begin
        mult_result = '0;

        // Explicit signed casts.
        // One multiplication operator is used for both modes.
        mult_result = $signed(A_ext) * $signed(B_ext);
    end

    // ============================================================
    // 4. PRODUCT / OVERFLOW LOGIC
    // ============================================================
    logic [PROD_WIDTH-1:0] product_comb;

    always_comb begin
        product_comb = '0;

        // Explicitly select the required product width.
        product_comb = mult_result[PROD_WIDTH-1:0];
    end

    // ============================================================
    // 5. REGISTERED OUTPUT STAGE
    // ============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            product   <= '0;
            valid_out <= 1'b0;
            overflow  <= 1'b0;
        end
        else begin
            // Default: valid is a one-cycle pulse.
            valid_out <= 1'b0;

            if (start_reg) begin

                // Register product.
                product <= product_comb;

                // ------------------------------------------------
                // Signed overflow
                // ------------------------------------------------
                if (signed_mode_reg) begin
                    // A signed DATA_WIDTH-bit result must have all
                    // upper bits equal to the sign bit.
                    overflow <=
                        (product_comb[PROD_WIDTH-1:DATA_WIDTH] !=
                         {DATA_WIDTH{product_comb[DATA_WIDTH-1]}});
                end

                // ------------------------------------------------
                // Unsigned overflow
                // ------------------------------------------------
                else begin
                    // An unsigned DATA_WIDTH-bit result must have
                    // all upper bits equal to zero.
                    overflow <=
                        (product_comb[PROD_WIDTH-1:DATA_WIDTH] !=
                         {DATA_WIDTH{1'b0}});
                end

                // Product and overflow are valid together.
                valid_out <= 1'b1;
            end
        end
    end

endmodule
