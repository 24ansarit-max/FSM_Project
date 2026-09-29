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

    //================================================================
    // WIDTHS
    //================================================================

    localparam int unsigned PTR_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    localparam int unsigned COUNT_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);


    //================================================================
    // SIZED CONSTANTS
    //================================================================

    localparam logic [COUNT_WIDTH-1:0] DEPTH_VALUE =
        DEPTH;

    localparam logic [COUNT_WIDTH-1:0] AF_THRESHOLD =
        ALMOST_FULL_THRESHOLD;

    localparam logic [COUNT_WIDTH-1:0] AE_THRESHOLD =
        ALMOST_EMPTY_THRESHOLD;


    //================================================================
    // GENERATE-TIME PARAMETER CHECKS
    //================================================================

    generate

        if (DEPTH < 1) begin : gen_bad_depth
            initial begin
                $error("DEPTH must be >= 1");
            end
        end

        if ((DEPTH > 1) &&
            ((DEPTH & (DEPTH - 1)) != 0)) begin : gen_bad_power2

            initial begin
                $error("DEPTH must be a power of 2");
            end

        end

        if (ALMOST_FULL_THRESHOLD > DEPTH) begin : gen_bad_af

            initial begin
                $error(
                    "ALMOST_FULL_THRESHOLD must be <= DEPTH"
                );
            end

        end

        if (ALMOST_EMPTY_THRESHOLD > DEPTH) begin : gen_bad_ae

            initial begin
                $error(
                    "ALMOST_EMPTY_THRESHOLD must be <= DEPTH"
                );
            end

        end

    endgenerate


    //================================================================
    // FIFO MEMORY
    //
    // Synchronous registered read allows Vivado to infer BRAM.
    //================================================================

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    //================================================================
    // POINTERS AND COUNT
    //================================================================

    logic [PTR_WIDTH-1:0]   wr_ptr;
    logic [PTR_WIDTH-1:0]   rd_ptr;

    logic [COUNT_WIDTH-1:0] count_reg;


    //================================================================
    // READ / WRITE CONTROL
    //================================================================

    logic write_valid;
    logic read_valid;

    assign write_valid = wr_en && !full;
    assign read_valid  = rd_en && !empty;


    //================================================================
    // FLAG GENERATION
    //================================================================

    assign full =
        (count_reg == DEPTH_VALUE);

    assign empty =
        (count_reg == '0);

    assign almost_full =
        (count_reg >= AF_THRESHOLD);

    assign almost_empty =
        (count_reg <= AE_THRESHOLD);


    //================================================================
    // FIFO COUNT OUTPUT
    //================================================================

    assign fifo_count = count_reg;


    //================================================================
    // SEQUENTIAL FIFO CONTROLLER
    //================================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            //--------------------------------------------------------
            // Synchronous reset
            //--------------------------------------------------------

            wr_ptr    <= '0;
            rd_ptr    <= '0;
            count_reg <= '0;

            rd_data <= '0;

            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;

        end
        else begin

            //--------------------------------------------------------
            // Invalid operation event pulses
            //--------------------------------------------------------

            overflow_flag  <= wr_en && full;
            underflow_flag <= rd_en && empty;


            //========================================================
            // WRITE PATH
            //========================================================

            if (write_valid) begin

                mem[wr_ptr] <= wr_data;

                //----------------------------------------------------
                // Explicit wrap-around
                //----------------------------------------------------

                if (wr_ptr == DEPTH - 1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;

            end


            //========================================================
            // READ PATH
            //========================================================

            if (read_valid) begin

                //----------------------------------------------------
                // Registered synchronous memory read
                //----------------------------------------------------

                rd_data <= mem[rd_ptr];

                //----------------------------------------------------
                // Explicit wrap-around
                //----------------------------------------------------

                if (rd_ptr == DEPTH - 1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;

            end


            //========================================================
            // DEDICATED UP/DOWN COUNTER
            //========================================================

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
