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

    output logic [(DEPTH <= 1 ? 1 : $clog2(DEPTH + 1))-1:0]
                                         fifo_count,

    output logic                         overflow_flag,
    output logic                         underflow_flag
);

    //============================================================
    // Widths
    //============================================================

    localparam int unsigned PTR_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    localparam int unsigned COUNT_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);


    //============================================================
    // FIFO memory
    //============================================================

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    //============================================================
    // Pointers and count
    //============================================================

    logic [PTR_WIDTH-1:0]   wr_ptr;
    logic [PTR_WIDTH-1:0]   rd_ptr;
    logic [COUNT_WIDTH-1:0] count_reg;


    //============================================================
    // Valid operations
    //============================================================

    logic write_valid;
    logic read_valid;


    //============================================================
    // Parameter validation
    //============================================================

    generate
        if (DEPTH < 1) begin : gen_invalid_depth
            initial $error("DEPTH must be >= 1");
        end

        if ((DEPTH > 1) && ((DEPTH & (DEPTH - 1)) != 0)) begin : gen_non_power_two
            initial $error("DEPTH must be a power of 2");
        end

        if (ALMOST_FULL_THRESHOLD > DEPTH) begin : gen_invalid_af
            initial $error("ALMOST_FULL_THRESHOLD must be <= DEPTH");
        end

        if (ALMOST_EMPTY_THRESHOLD > DEPTH) begin : gen_invalid_ae
            initial $error("ALMOST_EMPTY_THRESHOLD must be <= DEPTH");
        end
    endgenerate


    //============================================================
    // FLAG GENERATION
    //============================================================

    always_comb begin

        // Defaults prevent latches.
        full         = 1'b0;
        empty        = 1'b0;
        almost_full  = 1'b0;
        almost_empty = 1'b0;

        if (count_reg == DEPTH)
            full = 1'b1;

        if (count_reg == 0)
            empty = 1'b1;

        if (count_reg >= ALMOST_FULL_THRESHOLD)
            almost_full = 1'b1;

        if (count_reg <= ALMOST_EMPTY_THRESHOLD)
            almost_empty = 1'b1;

    end


    //============================================================
    // READ / WRITE ACCEPTANCE
    //============================================================

    always_comb begin

        write_valid = 1'b0;
        read_valid  = 1'b0;

        if (wr_en && !full)
            write_valid = 1'b1;

        if (rd_en && !empty)
            read_valid = 1'b1;

    end


    //============================================================
    // FIFO OUTPUT COUNT
    //============================================================

    assign fifo_count = count_reg;


    //============================================================
    // SEQUENTIAL FIFO
    //============================================================

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

            //====================================================
            // Error event pulses
            //====================================================

            overflow_flag  <= wr_en && full;
            underflow_flag <= rd_en && empty;


            //====================================================
            // WRITE
            //====================================================

            if (write_valid) begin

                mem[wr_ptr] <= wr_data;

                if (wr_ptr == DEPTH - 1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;

            end


            //====================================================
            // READ
            // Registered synchronous read.
            //====================================================

            if (read_valid) begin

                rd_data <= mem[rd_ptr];

                if (rd_ptr == DEPTH - 1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;

            end


            //====================================================
            // DEDICATED UP/DOWN COUNT
            //====================================================

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
