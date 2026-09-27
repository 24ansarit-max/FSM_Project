`timescale 1ns/1ps

module vending_machine #(
    parameter int unsigned NUM_ITEMS       = 4,
    parameter int unsigned NUM_DENOM       = 4,
    parameter int unsigned PRICE_WIDTH     = 8,
    parameter int unsigned BALANCE_WIDTH   = PRICE_WIDTH + 1,

    // Supported coin denominations
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

    // Controller outputs
    output logic                         dispense,
    output logic [PRICE_WIDTH-1:0]       change_amount,
    output logic                         error
);

    //==========================================================
    // State declaration
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
    // Coin validity
    //==========================================================
    logic coin_supported;

    always_comb begin
        coin_supported = 1'b0;

        if (NUM_DENOM >= 1 && coin_value == COIN_0)
            coin_supported = 1'b1;
        else if (NUM_DENOM >= 2 && coin_value == COIN_1)
            coin_supported = 1'b1;
        else if (NUM_DENOM >= 3 && coin_value == COIN_2)
            coin_supported = 1'b1;
        else if (NUM_DENOM >= 4 && coin_value == COIN_3)
            coin_supported = 1'b1;
    end

    //==========================================================
    // Balance arithmetic with explicit overflow protection
    //==========================================================
    logic [BALANCE_WIDTH-1:0] coin_ext;
    logic [BALANCE_WIDTH-1:0] balance_sum;
    logic                     balance_overflow;

    always_comb begin
        coin_ext = '0;
        coin_ext[PRICE_WIDTH-1:0] = coin_value;

        balance_sum = balance_reg + coin_ext;

        // Explicit unsigned overflow protection.
        // Saturate instead of allowing wrap-around.
        if (balance_sum < balance_reg)
            balance_overflow = 1'b1;
        else
            balance_overflow = 1'b0;
    end

    //==========================================================
    // Next-state logic
    //==========================================================
    always_comb begin
        next_state = state;

        case (state)

            //--------------------------------------------------
            // IDLE
            //--------------------------------------------------
            IDLE: begin
                if (coin_valid && coin_supported)
                    next_state = COIN_INSERTED;
            end

            //--------------------------------------------------
            // COIN INSERTED
            //--------------------------------------------------
            COIN_INSERTED: begin

                // Selection is allowed only when balance is
                // sufficient. Stock is checked in the next
                // state BEFORE dispensing is possible.
                if (item_select_valid &&
                    (balance_reg >= {{(BALANCE_WIDTH-PRICE_WIDTH){1'b0}},
                                      item_price})) begin

                    next_state = ITEM_SELECTED;
                end
            end

            //--------------------------------------------------
            // ITEM SELECTED
            //--------------------------------------------------
            ITEM_SELECTED: begin

                // IMPORTANT:
                // Out-of-stock is checked before DISPENSING.
                if (!item_stock) begin
                    next_state = OUT_OF_STOCK_ERROR;
                end
                else if (balance_reg < item_price) begin
                    next_state = COIN_INSERTED;
                end
                else begin
                    next_state = DISPENSING;
                end
            end

            //--------------------------------------------------
            // DISPENSING
            //--------------------------------------------------
            DISPENSING: begin
                if (balance_reg > item_price)
                    next_state = CHANGE_RETURN;
                else
                    next_state = IDLE;
            end

            //--------------------------------------------------
            // CHANGE RETURN
            //--------------------------------------------------
            CHANGE_RETURN: begin
                next_state = IDLE;
            end

            //--------------------------------------------------
            // OUT OF STOCK / ERROR
            //--------------------------------------------------
            OUT_OF_STOCK_ERROR: begin
                next_state = IDLE;
            end

            //--------------------------------------------------
            // Illegal state recovery
            //--------------------------------------------------
            default: begin
                next_state = IDLE;
            end

        endcase
    end

    //==========================================================
    // State register + data registers
    //==========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            balance_reg  <= '0;
            change_reg   <= '0;
        end
        else begin
            state <= next_state;

            //--------------------------------------------------
            // Accept coin only during transaction entry/
            // accumulation states.
            //--------------------------------------------------
            if (coin_valid &&
                coin_supported &&
                (state == IDLE || state == COIN_INSERTED)) begin

                if (balance_overflow)
                    balance_reg <= {BALANCE_WIDTH{1'b1}};
                else
                    balance_reg <= balance_sum;
            end

            //--------------------------------------------------
            // Calculate change after successful stock check.
            //--------------------------------------------------
            if ((state == ITEM_SELECTED) &&
                item_stock &&
                (balance_reg >= item_price)) begin

                change_reg <= balance_reg -
                              {{(BALANCE_WIDTH-PRICE_WIDTH){1'b0}},
                               item_price};
            end

            //--------------------------------------------------
            // Clear transaction after change/error.
            //--------------------------------------------------
            if ((state == CHANGE_RETURN) ||
                (state == OUT_OF_STOCK_ERROR)) begin

                balance_reg <= '0;
                change_reg  <= '0;
            end

            //--------------------------------------------------
            // Exact-payment transaction ends after dispensing.
            //--------------------------------------------------
            if ((state == DISPENSING) &&
                (balance_reg == item_price)) begin

                balance_reg <= '0;
                change_reg  <= '0;
            end
        end
    end

    //==========================================================
    // Output logic
    //==========================================================
    always_comb begin

        // Defaults prevent latch inference.
        dispense      = 1'b0;
        change_amount  = '0;
        error          = 1'b0;

        case (state)

            //--------------------------------------------------
            // DISPENSING
            //--------------------------------------------------
            DISPENSING: begin
                dispense = 1'b1;
            end

            //--------------------------------------------------
            // CHANGE RETURN
            //--------------------------------------------------
            CHANGE_RETURN: begin
                change_amount = change_reg[PRICE_WIDTH-1:0];
            end

            //--------------------------------------------------
            // OUT OF STOCK / ERROR
            //--------------------------------------------------
            OUT_OF_STOCK_ERROR: begin
                error = 1'b1;

                // Refund complete inserted balance.
                change_amount = balance_reg[PRICE_WIDTH-1:0];
            end

            default: begin
                dispense      = 1'b0;
                change_amount = '0;
                error         = 1'b0;
            end

        endcase
    end

endmodule
