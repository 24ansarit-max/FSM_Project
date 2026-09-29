`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned DATA_WIDTH              = 8,
    parameter int unsigned DEPTH                   = 16,
    parameter int unsigned ALMOST_FULL_THRESHOLD   = DEPTH - 2,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD  = 2
)(
    input  logic                       clk,
    input  logic                       rst,

    input  logic                       wr_en,
    input  logic [DATA_WIDTH-1:0]      wr_data,

    input  logic                       rd_en,

    output logic [DATA_WIDTH-1:0]      rd_data,
    output logic                       full,
    output logic                       empty,
    output logic                       almost_full,
    output logic                       almost_empty,

    output logic [$clog2(DEPTH+1)-1:0] fifo_count,

    output logic                       overflow_flag,
    output logic                       underflow_flag
);

    //============================================================
    // Derived parameters
    //============================================================

    localparam int unsigned ADDR_WIDTH  = $clog2(DEPTH);
    localparam int unsigned PTR_WIDTH   = ADDR_WIDTH + 1;
    localparam int unsigned COUNT_WIDTH = $clog2(DEPTH + 1);


    //============================================================
    // Parameter checking
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
    // FIFO memory
    //============================================================

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    //============================================================
    // Pointers
    //
    // Lower ADDR_WIDTH bits = memory address
    // MSB                  = wrap-around bit
    //============================================================

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;


    //============================================================
    // Accepted operations
    //============================================================

    logic do_write;
    logic do_read;

    always_comb begin
        do_write = wr_en && !full;
        do_read  = rd_en && !empty;
    end


    //============================================================
    // EMPTY FLAG
    //============================================================

    always_comb begin
        empty = (wr_ptr == rd_ptr);
    end


    //============================================================
    // FULL FLAG
    //
    // Full when:
    //   - address bits are equal
    //   - wrap bits are different
    //============================================================

    always_comb begin
        full =
            (wr_ptr[PTR_WIDTH-1] != rd_ptr[PTR_WIDTH-1]) &&
            (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    end


    //============================================================
    // FIFO COUNT
    //============================================================

    always_comb begin

        if (wr_ptr >= rd_ptr) begin
            fifo_count = wr_ptr - rd_ptr;
        end
        else begin
            fifo_count = DEPTH + wr_ptr - rd_ptr;
        end

    end


    //============================================================
    // ALMOST FULL / ALMOST EMPTY
    //============================================================

    always_comb begin

        almost_full  = (fifo_count >= ALMOST_FULL_THRESHOLD);
        almost_empty = (fifo_count <= ALMOST_EMPTY_THRESHOLD);

    end


    //============================================================
    // SEQUENTIAL FIFO
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

            // Error flags are one-cycle pulses
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

                // Attempted write while FIFO is full
                overflow_flag <= 1'b1;

            end


            //====================================================
            // READ
            //====================================================

            if (do_read) begin

                rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];

                rd_ptr <= rd_ptr + 1'b1;

            end
            else if (rd_en && empty) begin

                // Attempted read while FIFO is empty
                underflow_flag <= 1'b1;

            end

        end

    end

endmodule
