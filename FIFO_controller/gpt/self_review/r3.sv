`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned DATA_WIDTH              = 8,
    parameter int unsigned DEPTH                  = 16,
    parameter int unsigned ALMOST_FULL_THRESHOLD  = DEPTH - 1,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD = 1
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         wr_en,
    input  logic [DATA_WIDTH-1:0]        wr_data,
    input  logic                         rd_en,

    output logic [DATA_WIDTH-1:0]        rd_data,
    output logic                         full,
    output logic                         empty,
    output logic                         almost_full,
    output logic                         almost_empty,
    output logic [$clog2(DEPTH+1)-1:0]  fifo_count,
    output logic                         overflow_flag,
    output logic                         underflow_flag
);

    localparam int PTR_WIDTH = $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;
    logic [COUNT_WIDTH-1:0] count_reg;

    logic write_valid;
    logic read_valid;

    assign full         = (count_reg == DEPTH);
    assign empty        = (count_reg == 0);
    assign almost_full  = (count_reg >= ALMOST_FULL_THRESHOLD);
    assign almost_empty = (count_reg <= ALMOST_EMPTY_THRESHOLD);

    assign fifo_count = count_reg;

    assign write_valid = wr_en && !full;
    assign read_valid  = rd_en && !empty;

    generate
        if ((DEPTH < 1) || ((DEPTH & (DEPTH - 1)) != 0)) begin
            initial $error("DEPTH must be a positive power of 2");
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr         <= '0;
            rd_ptr         <= '0;
            count_reg      <= '0;
            rd_data        <= '0;
            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;
        end
        else begin

            // One-cycle error pulses
            overflow_flag  <= wr_en && full;
            underflow_flag <= rd_en && empty;

            // Write
            if (write_valid) begin
                mem[wr_ptr] <= wr_data;

                if (wr_ptr == DEPTH-1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            // Registered synchronous read
            if (read_valid) begin
                rd_data <= mem[rd_ptr];

                if (rd_ptr == DEPTH-1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            // FIFO count
            case ({write_valid, read_valid})
                2'b10: count_reg <= count_reg + 1'b1;
                2'b01: count_reg <= count_reg - 1'b1;
                2'b11: count_reg <= count_reg;
                2'b00: count_reg <= count_reg;
                default: count_reg <= count_reg;
            endcase
        end
    end

endmodule
