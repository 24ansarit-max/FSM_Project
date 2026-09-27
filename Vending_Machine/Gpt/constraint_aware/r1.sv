`timescale 1ns/1ps

module vending_machine #(
    parameter int COIN_WIDTH    = 4,
    parameter int PRICE_WIDTH   = 8,
    parameter int BALANCE_WIDTH = 9
)(
    input  logic                  clk,
    input  logic                  rst,              // synchronous active-high

    // Coin interface
    input  logic                  coin_valid,
    input  logic [COIN_WIDTH-1:0] coin_value,

    // Item interface
    input  logic                  item_select,
    input  logic [PRICE_WIDTH-1:0] item_price,
    input  logic                  stock_available,

    // Outputs
    output logic                  dispense_item,
    output logic [PRICE_WIDTH-1:0] change_amount,
    output logic                  error,

    // Optional balance/status output
    output logic [BALANCE_WIDTH-1:0] balance
);

    //============================================================
    // State definitions
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
    // Registers
    //============================================================
    logic [BALANCE_WIDTH-1:0] balance_reg;
    logic [PRICE_WIDTH-1:0]   change_reg;

    //============================================================
    // Combinational arithmetic
    //============================================================
    logic [BALANCE_WIDTH-1:0] coin_extended;
    logic [BALANCE_WIDTH-1:0] price_extended;
    logic [BALANCE_WIDTH:0]   balance_sum;

    assign coin_extended  = {{(BALANCE_WIDTH-COIN_WIDTH){1'b0}},
                             coin_value};

    assign price_extended = {{(BALANCE_WIDTH-PRICE_WIDTH){1'b0}},
                              item_price};

    // Extra bit provides overflow detection.
    assign balance_sum = {1'b0, balance_reg} +
                         {1'b0, coin_extended};

    //============================================================
    // 1. STATE REGISTER / DATA REGISTERS
    //============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            balance_reg <= '0;
            change_reg  <= '0;
        end
        else begin
            state <= next_state;

            // Accumulate coins only during an active transaction.
            if (coin_valid &&
                ((state == IDLE) || (state == COIN_INSERTED))) begin

                // Saturate instead of wrapping on accumulator overflow.
                if (balance_sum[BALANCE_WIDTH])
                    balance_reg <= {BALANCE_WIDTH{1'b1}};
                else
                    balance_reg <= balance_sum[BALANCE_WIDTH-1:0];
            end

            // Calculate change only after stock has been confirmed.
            if ((state == ITEM_SELECTED) &&
                stock_available &&
                (balance_reg >= price_extended)) begin

                change_reg <=
                    balance_reg[PRICE_WIDTH-1:0] - item_price;
            end

            // Transaction completed after change return.
            if (state == CHANGE_RETURN) begin
                balance_reg <= '0;
                change_reg  <= '0;
            end

            // Refund complete after out-of-stock error.
            if (state == OUT_OF_STOCK_ERR) begin
                balance_reg <= '0;
                change_reg  <= '0;
            end

            // Exact payment: no change is required.
            if ((state == DISPENSING) &&
                (balance_reg == price_extended)) begin

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

                // Item selection is accepted only when
                // sufficient balance already exists.
                if (item_select &&
                    (balance_reg >= price_extended)) begin

                    next_state = ITEM_SELECTED;
                end
            end

            ITEM_SELECTED: begin

                // Stock check has priority over dispensing.
                if (!stock_available) begin
                    next_state = OUT_OF_STOCK_ERR;
                end
                else if (balance_reg < price_extended) begin
                    next_state = COIN_INSERTED;
                end
                else begin
                    next_state = DISPENSING;
                end
            end

            DISPENSING: begin

                if (balance_reg > price_extended)
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
                error = 1'b1;

                // Refund the complete inserted balance.
                change_amount = balance_reg[PRICE_WIDTH-1:0];
            end

            default: begin
                dispense_item = 1'b0;
                change_amount = '0;
                error         = 1'b0;
            end

        endcase

        //========================================================
        // HARDWARE SAFETY INTERLOCK
        // This condition has priority over the FSM state.
        // Dispensing is physically/logically impossible when
        // the selected item is unavailable.
        //========================================================
        if (!stock_available)
            dispense_item = 1'b0;
    end

    //============================================================
    // Balance output
    //============================================================
    assign balance = balance_reg;

endmodule
