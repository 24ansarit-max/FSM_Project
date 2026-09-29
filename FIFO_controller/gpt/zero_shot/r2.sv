`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned DATA_WIDTH             = 8,
    parameter int unsigned DEPTH                  = 16,
    parameter int unsigned ALMOST_FULL_THRESHOLD  = DEPTH - 2,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD = 2
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

    output logic [$clog2(DEPTH+1)-1:0]   fifo_count,

    output logic                         overflow_flag,
    output logic                         underflow_flag
);

    //============================================================
    // Derived parameters
    //============================================================

    localparam int ADDR_WIDTH = $clog2(DEPTH);
    localparam int PTR_WIDTH  = ADDR_WIDTH + 1;
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);


    //============================================================
    // Parameter checks
    //============================================================

    initial begin

        if (DEPTH < 2)
            $error("DEPTH must be at least 2");

        if ((DEPTH & (DEPTH - 1)) != 0)
            $error("DEPTH must be a power of 2");

        if (ALMOST_FULL_THRESHOLD > DEPTH)
            $error("ALMOST_FULL_THRESHOLD must be <= DEPTH");

        if (ALMOST_EMPTY_THRESHOLD > DEPTH)
            $error("ALMOST_EMPTY_THRESHOLD must be <= DEPTH");

    end


    //============================================================
    // FIFO memory
    //============================================================

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    //============================================================
    // Read and write pointers
    //
    // Pointer width = address width + one wrap bit.
    //
    // Example for DEPTH = 16:
    //
    //   PTR_WIDTH = 5
    //
    //   [4]   -> wrap bit
    //   [3:0] -> memory address
    //============================================================

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;


    //============================================================
    // Operation enables
    //============================================================

    logic do_write;
    logic do_read;

    always_comb begin

        do_write = wr_en && !full;
        do_read  = rd_en && !empty;

    end


    //============================================================
    // EMPTY FLAG
    //
    // Both pointers identical means no unread entries.
    //============================================================

    always_comb begin

        empty = (wr_ptr == rd_ptr);

    end


    //============================================================
    // FULL FLAG
    //
    // FIFO is full when:
    //
    // 1. Address portions are equal
    // 2. Wrap bits are different
    //
    // This means the write pointer has completed exactly
    // one more circular traversal than the read pointer.
    //============================================================

    always_comb begin

        full =
            (wr_ptr[PTR_WIDTH-1] != rd_ptr[PTR_WIDTH-1]) &&
            (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    end


    //============================================================
    // FIFO COUNT
    //
    // Difference between write and read pointers.
    // The result ranges from 0 to DEPTH.
    //============================================================

    always_comb begin

        if (wr_ptr >= rd_ptr) begin

            fifo_count =
                wr_ptr - rd_ptr;

        end
        else begin

            fifo_count =
                DEPTH + wr_ptr - rd_ptr;

        end

    end


    //============================================================
    // ALMOST FLAGS
    //============================================================

    always_comb begin

        almost_full =
            (fifo_count >= ALMOST_FULL_THRESHOLD);

        almost_empty =
            (fifo_count <= ALMOST_EMPTY_THRESHOLD);

    end


    //============================================================
    // SEQUENTIAL FIFO LOGIC
    //============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            wr_ptr <= '0;
            rd_ptr <= '0;

            rd_data <= '0;

            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;

        end
        else begin

            //====================================================
            // Error flags are one-cycle pulses
            //====================================================

            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;


            //====================================================
            // WRITE
            //====================================================

            if (do_write) begin

                mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;

                wr_ptr <= wr_ptr + 1'b1;

            end
            else if (wr_en && full) begin

                // Write attempted while FIFO is full.
                overflow_flag <= 1'b1;

            end


            //====================================================
            // READ
            //====================================================

            if (do_read) begin

                rd_data <=
                    mem[rd_ptr[ADDR_WIDTH-1:0]];

                rd_ptr <= rd_ptr + 1'b1;

            end
            else if (rd_en && empty) begin

                // Read attempted while FIFO is empty.
                underflow_flag <= 1'b1;

            end

        end

    end

endmodule
