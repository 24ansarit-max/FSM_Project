`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned DATA_WIDTH              = 8,
    parameter int unsigned DEPTH                   = 16,
    parameter int unsigned ALMOST_FULL_THRESHOLD   = DEPTH - 1,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD  = 1
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

    output logic [$clog2(DEPTH):0]       fifo_count,

    output logic                         overflow_flag,
    output logic                         underflow_flag
);

    //======================================================================
    // Widths
    //
    // Pointer width:
    //   $clog2(DEPTH)
    //
    // Count width:
    //   $clog2(DEPTH)+1
    //
    // The extra count bit is mathematically required for a power-of-two
    // DEPTH because the count must represent DEPTH itself.
    // Example: DEPTH=16 requires values 0..16, hence 5 bits.
    //======================================================================

    localparam int unsigned PTR_WIDTH   = $clog2(DEPTH);
    localparam int unsigned COUNT_WIDTH = $clog2(DEPTH) + 1;


    //======================================================================
    // Generate-time parameter validation
    //======================================================================

    generate
        if (DEPTH < 2) begin : gen_invalid_depth_min
            initial begin
                $error("FIFO DEPTH must be >= 2.");
            end
        end

        if ((DEPTH & (DEPTH - 1)) != 0) begin : gen_invalid_depth_power2
            initial begin
                $error("FIFO DEPTH must be a power of 2.");
            end
        end

        if (ALMOST_FULL_THRESHOLD > DEPTH) begin : gen_invalid_af_threshold
            initial begin
                $error("ALMOST_FULL_THRESHOLD must be <= DEPTH.");
            end
        end

        if (ALMOST_EMPTY_THRESHOLD > DEPTH) begin : gen_invalid_ae_threshold
            initial begin
                $error("ALMOST_EMPTY_THRESHOLD must be <= DEPTH.");
            end
        end
    endgenerate


    //======================================================================
    // FIFO memory
    //
    // Synchronous read is used so that Vivado can infer block RAM.
    // ram_style explicitly requests BRAM implementation.
    //======================================================================

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    //======================================================================
    // Pointer and count registers
    //======================================================================

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;

    logic [COUNT_WIDTH-1:0] count_reg;


    //======================================================================
    // Read/write control signals
    //======================================================================

    logic write_valid;
    logic read_valid;


    //======================================================================
    // FLAG GENERATION
    //
    // Flags are purely combinational from the registered FIFO count.
    // Defaults are assigned before conditional logic, preventing latches.
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
    // FIFO COUNT OUTPUT
    //======================================================================

    assign fifo_count = count_reg;


    //======================================================================
    // READ / WRITE ACCEPTANCE
    //
    // Invalid operations are blocked.
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
    // POINTER / MEMORY / COUNT / ERROR REGISTERS
    //======================================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            // Synchronous active-high reset
            wr_ptr         <= '0;
            rd_ptr         <= '0;
            count_reg      <= '0;

            rd_data        <= '0;

            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;

        end
        else begin

            //==============================================================
            // Single-cycle invalid-operation pulses
            //==============================================================

            overflow_flag  <= wr_en && full;
            underflow_flag <= rd_en && empty;


            //==============================================================
            // WRITE PATH
            //
            // DEPTH is a power of 2, therefore the PTR_WIDTH-bit pointer
            // naturally wraps from DEPTH-1 back to zero.
            //==============================================================

            if (write_valid) begin

                mem[wr_ptr] <= wr_data;

                wr_ptr <= wr_ptr + 1'b1;

            end


            //==============================================================
            // READ PATH
            //
            // Registered synchronous read.
            // This is suitable for BRAM inference.
            //==============================================================

            if (read_valid) begin

                rd_data <= mem[rd_ptr];

                rd_ptr <= rd_ptr + 1'b1;

            end


            //==============================================================
            // DEDICATED UP/DOWN FIFO COUNT
            //
            // 10 : write only
            // 01 : read only
            // 11 : simultaneous read/write
            // 00 : idle
            //==============================================================

            case ({write_valid, read_valid})

                2'b10: begin
                    count_reg <= count_reg + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                end

                2'b01: begin
                    count_reg <= count_reg - {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
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
