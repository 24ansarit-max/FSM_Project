`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned DATA_WIDTH              = 8,
    parameter int unsigned DEPTH                   = 16,
    parameter int unsigned ALMOST_FULL_THRESHOLD   = DEPTH - 2,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD  = 2
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
    // Parameter widths
    //============================================================

    localparam int unsigned ADDR_WIDTH  = $clog2(DEPTH);
    localparam int unsigned COUNT_WIDTH = $clog2(DEPTH + 1);


    //============================================================
    // FIFO memory
    //============================================================

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    //============================================================
    // Read and write pointers
    //============================================================

    logic [ADDR_WIDTH-1:0] wr_ptr;
    logic [ADDR_WIDTH-1:0] rd_ptr;


    //============================================================
    // Operation control
    //============================================================

    logic do_write;
    logic do_read;


    //============================================================
    // Parameter checking
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
    // FIFO STATUS
    //============================================================

    always_comb begin

        empty = (fifo_count == '0);

        full = (fifo_count == DEPTH);

        almost_empty =
            (fifo_count <= ALMOST_EMPTY_THRESHOLD);

        almost_full =
            (fifo_count >= ALMOST_FULL_THRESHOLD);

    end


    //============================================================
    // ACCEPTED READ / WRITE OPERATIONS
    //============================================================

    always_comb begin

        do_write = wr_en && !full;
        do_read  = rd_en && !empty;

    end


    //============================================================
    // MEMORY + POINTERS
    //============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            wr_ptr  <= '0;
            rd_ptr  <= '0;
            rd_data <= '0;

        end
        else begin

            //====================================================
            // WRITE
            //====================================================

            if (do_write) begin

                mem[wr_ptr] <= wr_data;

                wr_ptr <= wr_ptr + 1'b1;

            end


            //====================================================
            // READ
            //====================================================

            if (do_read) begin

                rd_data <= mem[rd_ptr];

                rd_ptr <= rd_ptr + 1'b1;

            end

        end

    end


    //============================================================
    // FIFO COUNT
    //
    // Count changes only when exactly one operation occurs.
    // Simultaneous read + write leaves the count unchanged.
    //============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            fifo_count <= '0;

        end
        else if (do_write && !do_read) begin

            fifo_count <= fifo_count + 1'b1;

        end
        else if (do_read && !do_write) begin

            fifo_count <= fifo_count - 1'b1;

        end

    end


    //============================================================
    // ERROR FLAGS
    //
    // Registered one-cycle pulses.
    //============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;

        end
        else begin

            // Default: clear after one clock
            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;


            // Write attempted while full
            if (wr_en && full)
                overflow_flag <= 1'b1;


            // Read attempted while empty
            if (rd_en && empty)
                underflow_flag <= 1'b1;

        end

    end

endmodule
