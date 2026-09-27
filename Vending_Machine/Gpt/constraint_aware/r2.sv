`timescale 1ns/1ps

module vending_machine #(
    parameter int COIN_WIDTH    = 4,
    parameter int PRICE_WIDTH   = 8,
    parameter int BALANCE_WIDTH = 9
)(
    input  logic                   clk,
    input  logic                   rst,

    // Coin interface
    input  logic                   coin_valid,
    input  logic [COIN_WIDTH-1:0]  coin_value,

    // Item interface
    input  logic                   item_select,
    input  logic [PRICE_WIDTH-1:0] item_price,
    input  logic                   stock_available,

    // Outputs
    output logic                   dispense_item,
    output logic [PRICE_WIDTH-1:0] change_amount,
    output logic                   error,

    // Current inserted balance
    output logic [BALANCE_WIDTH-1:0] balance
);

    //============================================================
    // FSM STATES
    //============================================================
    typedef enum logic [2:0] {
        IDLE             = 3'b000,
        COIN_INSERTED    = 3'b001,
        ITEM_SELECTED    = 3'b010,
        DISPENSING       = 3'b011,
        CHANGE_RETURN    = 3'b100,
        OUT_OF_STOCK_ERR = 3'b101
    } state_t;

    state_t state, next_state;

    //============================================================
    // DATA REGISTERS
    //============================================================
    logic [BALANCE_WIDTH-1:0] balance_reg;
    logic [PRICE_WIDTH-1:0]   change_reg;

    //============================================================
    // ARITHMETIC
    //============================================================
    logic [BALANCE_WIDTH-1:0] coin_ext;
    logic [BALANCE_WIDTH-1:0] price_ext;
    logic [BALANCE_WIDTH:0]   balance_sum;

    assign coin_ext =
        {{(BALANCE_WIDTH-COIN_WIDTH){1'b0}}, coin_value};

    assign price_ext =
        {{(BALANCE_WIDTH-PRICE_WIDTH){1'b0}}, item_price};

    // Extra MSB detects accumulator overflow.
    assign balance_sum =
        {1'b0, balance_reg} + {1'b0, coin_ext};

    //============================================================
    // 1. STATE + DATA REGISTER
    // Synchronous active-high reset
    //============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            balance_reg <= '0;
            change_reg  <= '0;
        end
        else begin
            state <= next_state;

            // Accumulate a valid coin.
            if (coin_valid &&
                ((state == IDLE) || (state == COIN_INSERTED))) begin

                // Saturate on overflow.
                if (balance_sum[BALANCE_WIDTH])
                    balance_reg <= {BALANCE_WIDTH{1'b1}};
                else
                    balance_reg <= balance_sum[BALANCE_WIDTH-1:0];
            end

            // Store change only for a valid, in-stock purchase.
            if ((state == ITEM_SELECTED) &&
                stock_available &&
                (balance_reg >= price_ext)) begin

                change_reg <=
                    balance_reg[PRICE_WIDTH-1:0] - item_price;
            end

            // Clear transaction after change.
            if (state == CHANGE_RETURN) begin
                balance_reg <= '0;
                change_reg  <= '0;
            end

            // Clear transaction after refund.
            if (state == OUT_OF_STOCK_ERR) begin
                balance_reg <= '0;
                change_reg  <= '0;
            end

            // Exact payment needs no change.
            if ((state == DISPENSING) &&
                (balance_reg == price_ext)) begin

                balance_reg <= '0;
                change_reg  <= '0;
            end
        end
    end

    //============================================================
    // 2. NEXT-STATE LOGIC
    //============================================================
    always_comb begin

        next_state = state;

        case (state)

            IDLE: begin
                if (coin_valid)
                    next_state = COIN_INSERTED;
            end

            COIN_INSERTED: begin
                // Selection only after sufficient balance.
                if (item_select &&
                    (balance_reg >= price_ext)) begin
                    next_state = ITEM_SELECTED;
                end
            end

            ITEM_SELECTED: begin

                // Stock check has priority.
                if (!stock_available) begin
                    next_state = OUT_OF_STOCK_ERR;
                end

                // Insufficient balance cannot dispense.
                else if (balance_reg < price_ext) begin
                    next_state = COIN_INSERTED;
                end

                else begin
                    next_state = DISPENSING;
                end
            end

            DISPENSING: begin
                if (balance_reg > price_ext)
                    next_state = CHANGE_RETURN;
                else
                    next_state = IDLE;
            end

            CHANGE_RETURN: begin
                next_state = IDLE;
            end

            OUT_OF_STOCK_ERR: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    //============================================================
    // 3. OUTPUT LOGIC
    //============================================================
    always_comb begin

        dispense_item = 1'b0;
        change_amount = '0;
        error         = 1'b0;

        case (state)

            DISPENSING: begin
                dispense_item = 1'b1;
            end

            CHANGE_RETURN: begin
                change_amount = change_reg;
            end

            OUT_OF_STOCK_ERR: begin
                error         = 1'b1;
                change_amount = balance_reg[PRICE_WIDTH-1:0];
            end

            default: begin
                dispense_item = 1'b0;
                change_amount = '0;
                error         = 1'b0;
            end

        endcase

        //========================================================
        // HARD SAFETY INTERLOCK
        // This overrides the FSM output.
        //========================================================
        if (!stock_available)
            dispense_item = 1'b0;

    end

    //============================================================
    // Balance output
    //============================================================
    assign balance = balance_reg;

endmodule
