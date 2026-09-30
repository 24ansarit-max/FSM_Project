`timescale 1ns/1ps

module multiplier_16bit #(
    parameter int unsigned DATA_WIDTH = 16
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    start,

    input  logic [DATA_WIDTH-1:0]   A,
    input  logic [DATA_WIDTH-1:0]   B,
    input  logic                    signed_mode,

    output logic [(2*DATA_WIDTH)-1:0] product,
    output logic                    valid_out,
    output logic                    overflow
);

    // ============================================================
    // Width definitions
    // ============================================================
    localparam int EXT_WIDTH  = DATA_WIDTH + 1;
    localparam int PROD_WIDTH = 2 * DATA_WIDTH;
    localparam int MULT_WIDTH = 2 * EXT_WIDTH;

    // ============================================================
    // 1. Input registration
    // ============================================================
    logic [DATA_WIDTH-1:0] A_reg;
    logic [DATA_WIDTH-1:0] B_reg;
    logic                  signed_mode_reg;
    logic                  start_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            A_reg          <= '0;
            B_reg          <= '0;
            signed_mode_reg <= 1'b0;
            start_reg      <= 1'b0;
        end
        else begin
            A_reg           <= A;
            B_reg           <= B;
            signed_mode_reg <= signed_mode;
            start_reg       <= start;
        end
    end

    // ============================================================
    // 2. Mode-dependent sign/zero extension
    //
    // Signed mode:
    //   16-bit signed value -> 17-bit sign extension
    //
    // Unsigned mode:
    //   16-bit unsigned value -> 17-bit zero extension
    //
    // Both selected operands are represented as signed 17-bit
    // values before entering the single multiplier. In unsigned
    // mode the MSB is always zero, so the signed representation
    // still represents the intended positive unsigned value.
    // ============================================================
    logic signed [EXT_WIDTH-1:0] A_ext;
    logic signed [EXT_WIDTH-1:0] B_ext;

    always_comb begin
        A_ext = '0;
        B_ext = '0;

        if (signed_mode_reg) begin
            A_ext = $signed({A_reg[DATA_WIDTH-1], A_reg});
            B_ext = $signed({B_reg[DATA_WIDTH-1], B_reg});
        end
        else begin
            A_ext = $signed({1'b0, $unsigned(A_reg)});
            B_ext = $signed({1'b0, $unsigned(B_reg)});
        end
    end

    // ============================================================
    // 3. Single shared multiplier datapath
    //
    // This is the only multiplication operator in the design.
    // Vivado can map this multiplication to DSP48E1 resources.
    // ============================================================
    logic signed [MULT_WIDTH-1:0] mult_result;

    always_comb begin
        mult_result = '0;
        mult_result = $signed(A_ext) * $signed(B_ext);
    end

    // Explicit 32-bit product extraction.
    logic [PROD_WIDTH-1:0] product_comb;

    always_comb begin
        product_comb = '0;
        product_comb = mult_result[PROD_WIDTH-1:0];
    end

    // ============================================================
    // 4. Registered product, overflow and valid
    //
    // Latency:
    //   Cycle N   : A/B/mode/start registered
    //   Cycle N+1 : product/overflow/valid_out registered
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
                product <= product_comb;

                if (signed_mode_reg) begin
                    // 16-bit signed result must have bits [31:16]
                    // equal to sign extension of bit [15].
                    overflow <=
                        (product_comb[PROD_WIDTH-1:DATA_WIDTH] !=
                         {(DATA_WIDTH){product_comb[DATA_WIDTH-1]}});
                end
                else begin
                    // 16-bit unsigned result must have all upper
                    // bits equal to zero.
                    overflow <=
                        (product_comb[PROD_WIDTH-1:DATA_WIDTH] !=
                         {(DATA_WIDTH){1'b0}});
                end

                valid_out <= 1'b1;
            end
        end
    end

endmodule
