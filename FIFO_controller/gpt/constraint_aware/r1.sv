`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned DATA_WIDTH              = 8,
    parameter int unsigned DEPTH                   = 16,
    parameter int unsigned ALMOST_FULL_THRESHOLD   = DEPTH - 1,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD  = 1
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

    output logic [$clog2(DEPTH):0]   fifo_count,

    output logic                     overflow_flag,
    output logic                     underflow_flag
);

    //======================================================================
    // Parameter checks
    //
    // DEPTH must be a power of 2 and at least 2.
    // For a power-of-2 DEPTH, $clog2(DEPTH) is the pointer width.
    //
    // NOTE:
    // A count representing 0..DEPTH requires one additional bit because
    // DEPTH itself cannot be represented by only $clog2(DEPTH) bits.
    // Therefore fifo_count uses [$clog2(DEPTH):0].
    //======================================================================

    initial begin
        assert (DEPTH >= 2)
            else $error("DEPTH must be >= 2");

        assert ((DEPTH & (DEPTH - 1)) == 0)
            else $error("DEPTH must be a power of 2");

        assert (ALMOST_FULL_THRESHOLD <= DEPTH)
            else $error("ALMOST_FULL_THRESHOLD must be <= DEPTH");

        assert (ALMOST_EMPTY_THRESHOLD <= DEPTH)
            else $error("ALMOST_EMPTY_THRESHOLD must be <= DEPTH");
    end


    //======================================================================
    // Width definitions
    //======================================================================

    localparam int PTR_WIDTH = $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH) + 1;


    //======================================================================
    // FIFO storage
    //
    // Vivado can infer BRAM from this synchronous-read memory style.
    // DEPTH >= 16 is suitable for BRAM inference on Artix-7.
    //======================================================================

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    //======================================================================
    // FIFO pointers and count
    //======================================================================

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;

    logic [COUNT_WIDTH-1:0] count_reg;


    //======================================================================
    // Internal control signals
    //======================================================================

    logic write_valid;
    logic read_valid;


    //======================================================================
    // Flag generation
    //
    // Pure combinational logic.
    // Default assignments are explicitly provided.
    //======================================================================

    always_comb begin

        full         = 1'b0;
        empty        = 1'b0;
        almost_full  = 1'b0;
        almost_empty = 1'b0;

        if (count_reg == DEPTH) begin
            full = 1'b1;
        end

        if (count_reg == 0) begin
            empty = 1'b1;
        end

        if (count_reg >= ALMOST_FULL_THRESHOLD) begin
            almost_full = 1'b1;
        end

        if (count_reg <= ALMOST_EMPTY_THRESHOLD) begin
            almost_empty = 1'b1;
        end

    end


    //======================================================================
    // FIFO count output
    //
    // Dedicated registered up/down counter.
    //======================================================================

    assign fifo_count = count_reg;


    //======================================================================
    // Valid operations
    //
    // Writes while full are blocked.
    // Reads while empty are blocked.
    //======================================================================

    always_comb begin

        write_valid = 1'b0;
        read_valid  = 1'b0;

        if (wr_en && !full) begin
            write_valid = 1'b1;
        end

        if (rd_en && !empty) begin
            read_valid = 1'b1;
        end

    end


    //======================================================================
    // FIFO memory, pointer, count and error registers
    //
    // Synchronous read:
    //     rd_data <= mem[rd_ptr];
    //
    // This coding style allows Vivado to infer synchronous BRAM.
    //======================================================================

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

            //==============================================================
            // Single-cycle overflow / underflow pulses
            //==============================================================

            overflow_flag  <= wr_en && full;
            underflow_flag <= rd_en && empty;


            //==============================================================
            // WRITE
            //==============================================================

            if (write_valid) begin

                mem[wr_ptr] <= wr_data;

                // DEPTH is a power of 2, therefore natural pointer
                // wrap-around occurs automatically.
                wr_ptr <= wr_ptr + 1'b1;

            end


            //==============================================================
            // READ
            //==============================================================

            if (read_valid) begin

                // Registered synchronous BRAM read
                rd_data <= mem[rd_ptr];

                // DEPTH is a power of 2, so pointer wraps naturally.
                rd_ptr <= rd_ptr + 1'b1;

            end


            //==============================================================
            // DEDICATED UP/DOWN FIFO COUNTER
            //
            // 10 = write only  -> +1
            // 01 = read only   -> -1
            // 11 = read/write   -> unchanged
            // 00 = no operation -> unchanged
            //==============================================================

            case ({write_valid, read_valid})

                2'b10: begin
                    count_reg <= count_reg + 1'b1;
                end

                2'b01: begin
                    count_reg <= count_reg - 1'b1;
                end

                2'b11: begin
                    count_reg <= count_reg;
                end

                2'b00: begin
                    count_reg <= count_reg;
                end

                default: begin
                    count_reg <= count_reg;
                end

            endcase

        end

    end

endmodule
