`timescale 1ns/1ps

module sync_fifo #(
    parameter int unsigned DATA_WIDTH             = 8,
    parameter int unsigned DEPTH                  = 16,
    parameter int unsigned ALMOST_FULL_THRESHOLD  = DEPTH - 1,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD = 1
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

    //======================================================================
    // Parameter widths
    //
    // Pointer:
    //   $clog2(DEPTH)
    //
    // Count:
    //   $clog2(DEPTH+1)
    //
    // A count must represent 0 through DEPTH. Therefore, for a power-of-2
    // DEPTH, the count necessarily needs one more bit than $clog2(DEPTH).
    //======================================================================

    localparam int unsigned PTR_WIDTH   = $clog2(DEPTH);
    localparam int unsigned COUNT_WIDTH = $clog2(DEPTH + 1);


    //======================================================================
    // Generate-time parameter validation
    //======================================================================

    generate

        if (DEPTH < 2) begin : gen_invalid_depth_min
            initial begin
                assert (DEPTH >= 2)
                    else $error("DEPTH must be >= 2.");
            end
        end

        if ((DEPTH & (DEPTH - 1)) != 0) begin : gen_invalid_depth_power2
            initial begin
                assert ((DEPTH & (DEPTH - 1)) == 0)
                    else $error("DEPTH must be a power of 2.");
            end
        end

        if (ALMOST_FULL_THRESHOLD > DEPTH) begin : gen_invalid_af
            initial begin
                assert (ALMOST_FULL_THRESHOLD <= DEPTH)
                    else $error("ALMOST_FULL_THRESHOLD must be <= DEPTH.");
            end
        end

        if (ALMOST_EMPTY_THRESHOLD > DEPTH) begin : gen_invalid_ae
            initial begin
                assert (ALMOST_EMPTY_THRESHOLD <= DEPTH)
                    else $error("ALMOST_EMPTY_THRESHOLD must be <= DEPTH.");
            end
        end

    endgenerate


    //======================================================================
    // FIFO MEMORY
    //
    // Synchronous read is intentionally used:
    //
    //     rd_data <= mem[rd_ptr];
    //
    // This allows Vivado to infer synchronous Block RAM.
    //======================================================================

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    //======================================================================
    // POINTER / COUNT REGISTERS
    //======================================================================

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;

    logic [COUNT_WIDTH-1:0] count_reg;


    //======================================================================
    // READ / WRITE CONTROL
    //======================================================================

    logic write_valid;
    logic read_valid;

    assign write_valid = wr_en && !full;
    assign read_valid  = rd_en && !empty;


    //======================================================================
    // FLAG GENERATION
    //
    // Flags depend only on the registered FIFO count.
    // No combinational process is required, so there is no latch risk.
    //======================================================================

    assign full         = (count_reg == DEPTH);
    assign empty        = (count_reg == 0);

    assign almost_full  = (count_reg >= ALMOST_FULL_THRESHOLD);
    assign almost_empty = (count_reg <= ALMOST_EMPTY_THRESHOLD);

    assign fifo_count   = count_reg;


    //======================================================================
    // SEQUENTIAL FIFO CONTROLLER
    //
    // Active-high synchronous reset.
    //======================================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            //==============================================================
            // Reset pointer/count registers
            //==============================================================

            wr_ptr    <= '0;
            rd_ptr    <= '0;
            count_reg <= '0;

            //==============================================================
            // Reset registered read output
            //==============================================================

            rd_data <= '0;

            //==============================================================
            // Reset one-cycle error flags
            //==============================================================

            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;

        end
        else begin

            //==============================================================
            // Invalid operation pulses
            //
            // Write while full  -> overflow pulse
            // Read while empty  -> underflow pulse
            //==============================================================

            overflow_flag  <= wr_en && full;
            underflow_flag <= rd_en && empty;


            //==============================================================
            // WRITE PATH
            //
            // If full, write_valid = 0:
            //   - no memory write
            //   - no pointer increment
            //==============================================================

            if (write_valid) begin

                mem[wr_ptr] <= wr_data;

                // DEPTH is guaranteed to be a power of two.
                // Therefore the pointer naturally wraps to zero.
                wr_ptr <= wr_ptr + 1'b1;

            end


            //==============================================================
            // READ PATH
            //
            // Synchronous registered memory read.
            //
            // If empty, read_valid = 0:
            //   - no memory read
            //   - no pointer increment
            //   - rd_data retains its previous value
            //==============================================================

            if (read_valid) begin

                rd_data <= mem[rd_ptr];

                // DEPTH is a power of two, so natural binary overflow
                // performs the required wrap-around.
                rd_ptr <= rd_ptr + 1'b1;

            end


            //==============================================================
            // DEDICATED UP/DOWN FIFO COUNTER
            //
            // 10 -> write only       -> count + 1
            // 01 -> read only        -> count - 1
            // 11 -> read + write     -> count unchanged
            // 00 -> no operation     -> count unchanged
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
