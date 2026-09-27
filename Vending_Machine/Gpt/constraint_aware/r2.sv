`timescale 1ns/1ps

module vending_machine #(
    parameter int unsigned NUM_ITEMS     = 4,
    parameter int unsigned NUM_DENOMS    = 4,
    parameter int unsigned PRICE_WIDTH   = 8,
    parameter int unsigned BALANCE_WIDTH = PRICE_WIDTH + 1,

    // Coin denominations
    parameter logic [PRICE_WIDTH-1:0] COIN_0 = 8'd1,
    parameter logic [PRICE_WIDTH-1:0] COIN_1 = 8'd2,
    parameter logic [PRICE_WIDTH-1:0] COIN_2 = 8'd5,
    parameter logic [PRICE_WIDTH-1:0] COIN_3 = 8'd10
)(
    input  logic                         clk,
    input  logic                         rst,

    // Coin interface
    input  logic                         coin_valid,
    input  logic [PRICE_WIDTH-1:0]       coin_value,

    // Item interface
    input  logic [$clog2(NUM_ITEMS)-1:0] item_select,
    input  logic                         item_select_valid,
    input  logic [PRICE_WIDTH-1:0]       item_price,
    input  logic                         item_stock,

    // Outputs
    output logic                         dispense,
    output logic [PRICE_WIDTH-1:0]       change_amount,
    output logic                         error
);

    //==========================================================
    // FSM
    //==========================================================
    typedef enum logic [2:0] {
        IDLE,
        COIN_INSERTED,
        ITEM_SELECTED,
        DISPENSING,
        CHANGE_RETURN,
        OUT_OF_STOCK_ERROR
    } state_t;

    state_t state, next_state;

    //==========================================================
    // Registers
    //==========================================================
    logic [BALANCE_WIDTH-1:0] balance_reg;
    logic [BALANCE_WIDTH-1:0] change_reg;

    //==========================================================
    // Extended price
    //==========================================================
    logic [BALANCE_WIDTH-1:0] price_ext;

    always_comb begin
        price_ext = '0;
        price_ext[PRICE_WIDTH-1:0] = item_price;
    end

    //==========================================================
    // Coin validation
    //==========================================================
    logic coin_supported;

    always_comb begin
        coin_supported = 1'b0;

        case (NUM_DENOMS)
            1: begin
                if (coin_value == COIN_0)
                    coin_supported = 1'b1;
            end

            2: begin
                if ((coin_value == COIN_0) ||
                    (coin_value == COIN_1))
                    coin_supported = 1'b1;
            end

            3: begin
                if ((coin_value == COIN_0) ||
                    (coin_value == COIN_1) ||
                    (coin_value == COIN_2))
                    coin_supported = 1'b1;
            end

            default: begin
                if ((coin_value == COIN_0) ||
                    (coin_value == COIN_1) ||
                    (coin_value == COIN_2) ||
                    (coin_value == COIN_3))
                    coin_supported = 1'b1;
            end
        endcase
    end

    //==========================================================
    // Protected balance arithmetic
    //==========================================================
    logic [BALANCE_WIDTH-1:0] coin_ext;
    logic [BALANCE_WIDTH:0]   balance_sum_ext;
    logic                     balance_overflow;

    always_comb begin
        coin_ext = '0;
        coin_ext[PRICE_WIDTH-1:0] = coin_value;

        balance_sum_ext = {1'b0, balance_reg} +
                          {1'b0, coin_ext};

        balance_overflow = balance_sum_ext[BALANCE_WIDTH];
    end

    //==========================================================
    // 1. STATE REGISTER
    //==========================================================
    always_ff @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    //==========================================================
    // 2. NEXT-STATE LOGIC
    //==========================================================
    always_comb begin
        next_state = state;

        case (state)

            IDLE: begin
                if (coin_valid && coin_supported)
                    next_state = COIN_INSERTED;
            end

            COIN_INSERTED: begin
                // Selection is accepted only after sufficient
                // balance is available.
                if (item_select_valid &&
                    (balance_reg >= price_ext)) begin
                    next_state = ITEM_SELECTED;
                end
            end

            ITEM_SELECTED: begin
                // Stock check has priority over dispensing.
                if (!item_stock) begin
                    next_state = OUT_OF_STOCK_ERROR;
                end
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

            OUT_OF_STOCK_ERROR: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    //==========================================================
    // 3. DATA REGISTERS
    //==========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            balance_reg <= '0;
            change_reg  <= '0;
        end
        else begin

            // Accumulate valid supported coins.
            // Saturate on overflow instead of wrapping around.
            if (coin_valid &&
                coin_supported &&
                ((state == IDLE) ||
                 (state == COIN_INSERTED))) begin

                if (balance_overflow)
                    balance_reg <= {BALANCE_WIDTH{1'b1}};
                else
                    balance_reg <= balance_sum_ext[BALANCE_WIDTH-1:0];
            end

            // Calculate change only after the item has been
            // confirmed to be in stock.
            if ((state == ITEM_SELECTED) &&
                item_stock &&
                (balance_reg >= price_ext)) begin

                change_reg <= balance_reg - price_ext;
            end

            // Exact payment: transaction ends after dispensing.
            if ((state == DISPENSING) &&
                (balance_reg == price_ext)) begin

                balance_reg <= '0;
                change_reg  <= '0;
            end

            // Overpayment transaction is cleared after
            // CHANGE_RETURN.
            if (state == CHANGE_RETURN) begin
                balance_reg <= '0;
                change_reg  <= '0;
            end

            // Out-of-stock transaction is cleared after refund.
            if (state == OUT_OF_STOCK_ERROR) begin
                balance_reg <= '0;
                change_reg  <= '0;
            end
        end
    end

    //==========================================================
    // 4. OUTPUT LOGIC
    //==========================================================
    always_comb begin

        // Defaults prevent latch inference.
        dispense     = 1'b0;
        change_amount = '0;
        error         = 1'b0;

        case (state)

            DISPENSING: begin
                dispense = 1'b1;
            end

            CHANGE_RETURN: begin
                change_amount = change_reg[PRICE_WIDTH-1:0];
            end

            OUT_OF_STOCK_ERROR: begin
                error = 1'b1;

                // Refund the complete inserted balance.
                change_amount =
                    balance_reg[PRICE_WIDTH-1:0];
            end

            default: begin
                dispense      = 1'b0;
                change_amount = '0;
                error         = 1'b0;
            end

        endcase
    end

endmodule
