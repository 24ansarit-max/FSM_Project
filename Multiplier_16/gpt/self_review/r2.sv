`timescale 1ns/1ps

module multiplier_16bit #(
    parameter int unsigned DATA_WIDTH = 16
)(
    input  logic                       clk,
    input  logic                       rst,
    input  logic [DATA_WIDTH-1:0]      A,
    input  logic [DATA_WIDTH-1:0]      B,
    input  logic                       signed_mode,
    input  logic                       start,

    output logic [(2*DATA_WIDTH)-1:0]  product,
    output logic                       valid_out,
    output logic                       overflow
);

    localparam int unsigned EXT_WIDTH  = DATA_WIDTH + 1;
    localparam int unsigned PROD_WIDTH = 2 * DATA_WIDTH;
    localparam int unsigned MULT_WIDTH = 2 * EXT_WIDTH;

    // ============================================================
    // INPUT PIPELINE REGISTER
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
    // MODE-DEPENDENT OPERAND EXTENSION
    // ============================================================
    logic signed [EXT_WIDTH-1:0] A_ext;
    logic signed [EXT_WIDTH-1:0] B_ext;

    always_comb begin
        A_ext = '0;
        B_ext = '0;

        if (signed_mode_reg) begin
            // Two's-complement sign extension.
            A_ext = $signed({A_reg[DATA_WIDTH-1], A_reg});
            B_ext = $signed({B_reg[DATA_WIDTH-1], B_reg});
        end
        else begin
            // Explicit zero extension.
            A_ext = $signed({1'b0, $unsigned(A_reg)});
            B_ext = $signed({1'b0, $unsigned(B_reg)});
        end
    end

    // ============================================================
    // SINGLE SHARED MULTIPLIER DATAPATH
    // ============================================================
    logic signed [MULT_WIDTH-1:0] mult_result;

    always_comb begin
        mult_result = '0;
        mult_result = $signed(A_ext) * $signed(B_ext);
    end

    // ============================================================
    // PRODUCT AND OVERFLOW LOGIC
    // ============================================================
    logic [PROD_WIDTH-1:0] product_comb;
    logic                  overflow_comb;

    always_comb begin
        product_comb  = '0;
        overflow_comb = 1'b0;

        // Required full-precision product width.
        product_comb = mult_result[PROD_WIDTH-1:0];

        if (signed_mode_reg) begin
            // Signed result fits when the upper half is the
            // sign extension of the result's MSB.
            overflow_comb =
                (product_comb[PROD_WIDTH-1:DATA_WIDTH] !=
                 {DATA_WIDTH{product_comb[DATA_WIDTH-1]}});
        end
        else begin
            // Unsigned result fits when the upper half is zero.
            overflow_comb =
                (product_comb[PROD_WIDTH-1:DATA_WIDTH] !=
                 {DATA_WIDTH{1'b0}});
        end
    end

    // ============================================================
    // OUTPUT PIPELINE REGISTER
    //
    // Latency:
    //
    // Cycle N:
    //   A, B, signed_mode, start captured
    //
    // Cycle N+1:
    //   product, overflow, valid_out generated
    // ============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            product   <= '0;
            overflow  <= 1'b0;
            valid_out <= 1'b0;
        end
        else begin
            valid_out <= 1'b0;

            if (start_reg) begin
                product   <= product_comb;
                overflow  <= overflow_comb;
                valid_out <= 1'b1;
            end
        end
    end

endmodule
