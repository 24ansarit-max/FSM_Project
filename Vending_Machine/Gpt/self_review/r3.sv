`timescale 1ns/1ps

module vending_machine #(
    parameter int COIN_WIDTH    = 4,
    parameter int PRICE_WIDTH   = 8,
    parameter int BALANCE_WIDTH = 9
)(
    input  logic                     clk,
    input  logic                     rst,

    // Coin interface
    input  logic                     coin_valid,
    input  logic [COIN_WIDTH-1:0]    coin_value,

    // Item interface
    input  logic                     item_select,
    input  logic [PRICE_WIDTH-1:0]   item_price,
    input  logic                     stock_available,

    // Outputs
    output logic                     dispense_item,
    output logic [BALANCE_WIDTH-1:0] change_amount,
    output logic                     error,

    // Current inserted balance
    output logic [BALANCE_WIDTH-1:0] balance
);

    //==========================================================
    // FSM STATES
    //==========================================================
    typedef enum logic [2:0] {
        IDLE             = 3'b000,
        COIN_INSERTED    = 3'b001,
        ITEM_SELECTED    = 3'b010,
        DISPENSING       = 3'b011,
        CHANGE_RETURN    = 3'b100,
        OUT_OF_STOCK_ERR = 3'b101
    } state_t;

    state_t state;
    state_t next_state;

    //==========================================================
    // TRANSACTION REGISTERS
    //==========================================================
    logic [BALANCE_WIDTH-1:0] balance_reg;

    logic [PRICE_WIDTH-1:0] selected_price_reg;

    logic selected_stock_reg;

    logic [BALANCE_WIDTH-1:0] change_reg;

    //==========================================================
    // WIDTH-EXTENDED OPERANDS
    //==========================================================
    logic [BALANCE_WIDTH-1:0] coin_extended;
    logic [BALANCE_WIDTH-1:0] price_extended;

    logic [BALANCE_WIDTH:0] balance_sum;

    logic [BALANCE_WIDTH:0] change_difference;

    localparam logic [BALANCE_WIDTH-1:0] MAX_BALANCE =
        {BALANCE_WIDTH{1'b1}};

    //==========================================================
    // EXPLICIT ZERO EXTENSION
    //==========================================================
    always_comb begin
        coin_extended  = '0;
        price_extended = '0;

        coin_extended[COIN_WIDTH-1:0] =
            coin_value;

        price_extended[PRICE_WIDTH-1:0] =
            selected_price_reg;
    end

    //==========================================================
    // BALANCE ADDITION
    // Extra bit detects overflow.
    //==========================================================
    always_comb begin
        balance_sum =
            {1'b0, balance_reg} +
            {1'b0, coin_extended};
    end

    //==========================================================
    // WIDTH-SAFE CHANGE CALCULATION
    //==========================================================
    always_comb begin
        change_difference = '0;

        if (balance_reg >= price_extended) begin
            change_difference =
                {1'b0, balance_reg} -
                {1'b0, price_extended};
        end
    end

    //==========================================================
    // 1. STATE REGISTER
    // Synchronous active-high reset
    //==========================================================
    always_ff @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    //==========================================================
    // 2. DATA REGISTERS
    //==========================================================
    always_ff @(posedge clk) begin

        if (rst) begin
            balance_reg        <= '0;
            selected_price_reg <= '0;
            selected_stock_reg <= 1'b0;
            change_reg         <= '0;
        end
        else begin

            //==================================================
            // COIN ACCUMULATION
            // Coins accepted only in IDLE / COIN_INSERTED.
            //==================================================
            if (coin_valid &&
                ((state == IDLE) ||
                 (state == COIN_INSERTED))) begin

                // Saturating accumulator
                if (balance_sum[BALANCE_WIDTH])
                    balance_reg <= MAX_BALANCE;
                else
                    balance_reg <= balance_sum[BALANCE_WIDTH-1:0];
            end

            //==================================================
            // LATCH ITEM INFORMATION
            //
            // Selection is accepted only with sufficient
            // balance.
            //==================================================
            if ((state == COIN_INSERTED) &&
                item_select &&
                (balance_reg >= price_extended)) begin

                selected_price_reg <= item_price;
                selected_stock_reg <= stock_available;
            end

            //==================================================
            // CALCULATE CHANGE
            //==================================================
            if ((state == ITEM_SELECTED) &&
                selected_stock_reg &&
                (balance_reg >= price_extended)) begin

                change_reg <=
                    change_difference[BALANCE_WIDTH-1:0];
            end

            //==================================================
            // TRANSACTION COMPLETE AFTER CHANGE
            //==================================================
            if (state == CHANGE_RETURN) begin
                balance_reg        <= '0;
                selected_price_reg <= '0;
                selected_stock_reg <= 1'b0;
                change_reg         <= '0;
            end

            //==================================================
            // REFUND COMPLETE
            //==================================================
            if (state == OUT_OF_STOCK_ERR) begin
                balance_reg        <= '0;
                selected_price_reg <= '0;
                selected_stock_reg <= 1'b0;
                change_reg         <= '0;
            end

            //==================================================
            // EXACT PAYMENT
            //==================================================
            if ((state == DISPENSING) &&
                (balance_reg == price_extended)) begin

                balance_reg        <= '0;
                selected_price_reg <= '0;
                selected_stock_reg <= 1'b0;
                change_reg         <= '0;
            end

        end
    end

    //==========================================================
    // 3. NEXT-STATE LOGIC
    //==========================================================
    always_comb begin

        // Default prevents latches.
        next_state = state;

        case (state)

            //==================================================
            // IDLE
            //==================================================
            IDLE: begin
                if (coin_valid)
                    next_state = COIN_INSERTED;
            end

            //==================================================
            // COIN INSERTED
            //
            // Insufficient balance -> wait here for more coins.
            //==================================================
            COIN_INSERTED: begin

                if (item_select &&
                    (balance_reg >= price_extended)) begin

                    next_state = ITEM_SELECTED;
                end

            end

            //==================================================
            // ITEM SELECTED
            //==================================================
            ITEM_SELECTED: begin

                // Out-of-stock has priority.
                if (!selected_stock_reg) begin
                    next_state = OUT_OF_STOCK_ERR;
                end

                // Defensive insufficient-balance protection.
                else if (balance_reg < price_extended) begin
                    next_state = COIN_INSERTED;
                end

                // Only valid funded stock reaches dispensing.
                else begin
                    next_state = DISPENSING;
                end

            end

            //==================================================
            // DISPENSING
            //==================================================
            DISPENSING: begin

                if (balance_reg > price_extended)
                    next_state = CHANGE_RETURN;
                else
                    next_state = IDLE;

            end

            //==================================================
            // CHANGE RETURN
            //==================================================
            CHANGE_RETURN: begin
                next_state = IDLE;
            end

            //==================================================
            // OUT OF STOCK / ERROR
            //==================================================
            OUT_OF_STOCK_ERR: begin
                next_state = IDLE;
            end

            //==================================================
            // ILLEGAL STATE RECOVERY
            //==================================================
            default: begin
                next_state = IDLE;
            end

        endcase
    end

    //==========================================================
    // 4. OUTPUT LOGIC
    //==========================================================
    always_comb begin

        // Default outputs
        dispense_item = 1'b0;
        change_amount = '0;
        error         = 1'b0;

        case (state)

            //==================================================
            // DISPENSING
            //==================================================
            DISPENSING: begin
                dispense_item = 1'b1;
            end

            //==================================================
            // CHANGE RETURN
            //==================================================
            CHANGE_RETURN: begin
                change_amount = change_reg;
            end

            //==================================================
            // OUT OF STOCK / ERROR
            //==================================================
            OUT_OF_STOCK_ERR: begin
                error = 1'b1;

                // Full inserted balance is refunded.
                change_amount = balance_reg;
            end

            default: begin
                dispense_item = 1'b0;
                change_amount = '0;
                error         = 1'b0;
            end

        endcase

        //======================================================
        // HARDWARE STOCK SAFETY INTERLOCK
        //
        // This overrides the FSM output.
        //======================================================
        if (!stock_available)
            dispense_item = 1'b0;

    end

    //==========================================================
    // BALANCE OUTPUT
    //==========================================================
    assign balance = balance_reg;

endmodule
