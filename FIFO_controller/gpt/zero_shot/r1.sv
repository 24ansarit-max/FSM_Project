`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned DATA_WIDTH              = 8,
    parameter int unsigned DEPTH                   = 16,
    parameter int unsigned ALMOST_FULL_THRESHOLD   = DEPTH - 2,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD  = 2
)(
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     wr_en,
    input  logic [DATA_WIDTH-1:0]    wr_data,

    input  logic                     rd_en,

    output logic [DATA_WIDTH-1:0]    rd_data,

    output logic                     full,
    output logic                     empty,
    output logic                     almost_full,
    output logic                     almost_empty,

    output logic [$clog2(DEPTH+1)-1:0] fifo_count,

    output logic                     overflow_flag,
    output logic                     underflow_flag
);

    //============================================================
    // Parameter checks
    //============================================================

    initial begin
        if (DEPTH < 2)
            $error("DEPTH must be >= 2");

        if ((DEPTH & (DEPTH - 1)) != 0)
            $error("DEPTH must be a power of 2");

        if (ALMOST_FULL_THRESHOLD > DEPTH)
            $error("ALMOST_FULL_THRESHOLD must be <= DEPTH");

        if (ALMOST_EMPTY_THRESHOLD > DEPTH)
            $error("ALMOST_EMPTY_THRESHOLD must be <= DEPTH");
    end


    //============================================================
    // Derived widths
    //
    // Address needs log2(DEPTH) bits.
    // Extra MSB distinguishes wrapped/full from empty.
    //============================================================

    localparam int ADDR_WIDTH = $clog2(DEPTH);
    localparam int PTR_WIDTH  = ADDR_WIDTH + 1;
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);


    //============================================================
    // FIFO memory
    //============================================================

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    //============================================================
    // Read/write pointers
    //
    // Lower ADDR_WIDTH bits:
    //     memory address
    //
    // Extra MSB:
    //     wrap-around information
    //============================================================

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;

    logic [PTR_WIDTH-1:0] wr_ptr_next;
    logic [PTR_WIDTH-1:0] rd_ptr_next;


    //============================================================
    // Read/write acceptance
    //
    // An operation is accepted only if it does not violate the
    // FIFO boundary condition.
    //============================================================

    logic do_write;
    logic do_read;

    always_comb begin

        do_write = wr_en && !full;
        do_read  = rd_en && !empty;

    end


    //============================================================
    // Next pointer logic
    //============================================================

    always_comb begin

        wr_ptr_next = wr_ptr;
        rd_ptr_next = rd_ptr;

        if (do_write)
            wr_ptr_next = wr_ptr + 1'b1;

        if (do_read)
            rd_ptr_next = rd_ptr + 1'b1;

    end


    //============================================================
    // Empty detection
    //
    // FIFO is empty when both pointers are identical.
    //============================================================

    always_comb begin

        empty = (wr_ptr == rd_ptr);

    end


    //============================================================
    // Full detection
    //
    // Full occurs when the write pointer has caught the read
    // pointer after exactly one complete memory wrap.
    //
    // With an extra MSB:
    //
    //     upper/wrap bit differs
    //     address bits are equal
    //============================================================

    always_comb begin

        full =
            (wr_ptr[PTR_WIDTH-1] != rd_ptr[PTR_WIDTH-1]) &&
            (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    end


    //============================================================
    // FIFO count
    //
    // Difference between pointers modulo 2*DEPTH.
    // The lower COUNT_WIDTH bits represent 0..DEPTH.
    //============================================================

    always_comb begin

        if (wr_ptr >= rd_ptr)
            fifo_count = wr_ptr - rd_ptr;
        else
            fifo_count =
                (DEPTH + wr_ptr) - rd_ptr;

    end


    //============================================================
    // Almost-full / almost-empty flags
    //============================================================

    always_comb begin

        almost_full =
            (fifo_count >= ALMOST_FULL_THRESHOLD);

        almost_empty =
            (fifo_count <= ALMOST_EMPTY_THRESHOLD);

    end


    //============================================================
    // Sequential FIFO operation
    //============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            wr_ptr <= '0;
            rd_ptr <= '0;

            rd_data <= '0;

            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;

        end
        else begin

            //----------------------------------------------------
            // Default: error flags are one-cycle pulses.
            //----------------------------------------------------
            overflow_flag <= 1'b0;
            underflow_flag <= 1'b0;


            //----------------------------------------------------
            // Write operation
            //----------------------------------------------------
            if (do_write) begin

                mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;

            end
            else if (wr_en && full) begin

                // Write was attempted while FIFO was full.
                overflow_flag <= 1'b1;

            end


            //----------------------------------------------------
            // Read operation
            //----------------------------------------------------
            if (do_read) begin

                rd_data <=
                    mem[rd_ptr[ADDR_WIDTH-1:0]];

            end
            else if (rd_en && empty) begin

                // Read was attempted while FIFO was empty.
                underflow_flag <= 1'b1;

            end


            //----------------------------------------------------
            // Update pointers
            //----------------------------------------------------
            wr_ptr <= wr_ptr_next;
            rd_ptr <= rd_ptr_next;

        end

    end

endmodule
