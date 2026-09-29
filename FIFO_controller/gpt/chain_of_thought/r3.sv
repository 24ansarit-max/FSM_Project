`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH = 16,
    parameter int unsigned ALMOST_FULL_THRESHOLD = DEPTH - 1,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD = 1
)(
    input  logic clk,
    input  logic rst,

    input  logic wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,

    input  logic rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,

    output logic full,
    output logic empty,
    output logic almost_full,
    output logic almost_empty,

    // Protected against zero-width vector when DEPTH = 1
    output logic [(DEPTH <= 1 ? 1 : $clog2(DEPTH + 1))-1:0] fifo_count,

    output logic overflow_flag,
    output logic underflow_flag
);

    //============================================================
    // Parameter-dependent widths
    //============================================================

    localparam int PTR_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    localparam int COUNT_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);


    //============================================================
    // FIFO memory
    //============================================================

    logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];


    //============================================================
    // Read / write pointers
    //============================================================

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;


    //============================================================
    // Valid operation signals
    //============================================================

    logic write_valid;
    logic read_valid;


    //============================================================
    // FIFO status flags
    //============================================================

    always_comb begin

        full = (fifo_count == DEPTH);

        empty = (fifo_count == 0);

        almost_full =
            (fifo_count >= ALMOST_FULL_THRESHOLD);

        almost_empty =
            (fifo_count <= ALMOST_EMPTY_THRESHOLD);

    end


    //============================================================
    // Accepted operations
    //============================================================

    assign write_valid = wr_en && !full;

    assign read_valid = rd_en && !empty;


    //============================================================
    // Sequential FIFO controller
    //============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            //----------------------------------------------------
            // Reset pointers
            //----------------------------------------------------

            wr_ptr <= '0;
            rd_ptr <= '0;

            //----------------------------------------------------
            // Reset FIFO count
            //----------------------------------------------------

            fifo_count <= '0;

            //----------------------------------------------------
            // Reset read data
            //----------------------------------------------------

            rd_data <= '0;

            //----------------------------------------------------
            // Reset error flags
            //----------------------------------------------------

            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;

        end
        else begin

            //----------------------------------------------------
            // Overflow / underflow event flags
            //
            // These indicate an invalid request in this cycle.
            //----------------------------------------------------

            overflow_flag <= wr_en && full;

            underflow_flag <= rd_en && empty;


            //----------------------------------------------------
            // WRITE OPERATION
            //----------------------------------------------------

            if (write_valid) begin

                memory[wr_ptr] <= wr_data;

                // Explicit wrap-around
                if (wr_ptr == DEPTH - 1) begin
                    wr_ptr <= '0;
                end
                else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end

            end


            //----------------------------------------------------
            // READ OPERATION
            //----------------------------------------------------

            if (read_valid) begin

                // Registered read data
                rd_data <= memory[rd_ptr];

                // Explicit wrap-around
                if (rd_ptr == DEPTH - 1) begin
                    rd_ptr <= '0;
                end
                else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end

            end


            //----------------------------------------------------
            // FIFO COUNT UPDATE
            //----------------------------------------------------

            case ({write_valid, read_valid})

                // Write only
                2'b10: begin
                    fifo_count <= fifo_count + 1'b1;
                end

                // Read only
                2'b01: begin
                    fifo_count <= fifo_count - 1'b1;
                end

                // Both accepted:
                // one enters and one leaves
                2'b11: begin
                    fifo_count <= fifo_count;
                end

                // No operation
                2'b00: begin
                    fifo_count <= fifo_count;
                end

                default: begin
                    fifo_count <= fifo_count;
                end

            endcase

        end

    end

endmodule
