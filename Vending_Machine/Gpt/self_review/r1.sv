`timescale 1ns/1ps

module vending_machine #(
    parameter int COIN_WIDTH    = 4,
    parameter int PRICE_WIDTH   = 8,
    parameter int BALANCE_WIDTH = 9
)(
    input  logic                     clk,
    input  logic                     rst,

    //==========================================================
    // Coin interface
    // coin_value represents the actual denomination:
    // e.g. 1, 2, 5, 10
    //==========================================================
    input  logic                     coin_valid,
    input  logic [COIN_WIDTH-1:0]     coin_value,

    //==========================================================
    // Item selection
    //==========================================================
    input  logic                     item_select,

    // Information for currently selected item
    input  logic [PRICE_WIDTH-1:0]    item_price,
    input  logic                     stock_available,

    //==========================================================
    // Outputs
    //==========================================================
    output logic                     dispense_item,
    output logic [PRICE_WIDTH-1:0]   change_amount,
    output logic                     error,

    // Current inserted balance
    output logic [BALANCE_WIDTH-1:0] balance
);

    //==========================================================
    // Parameter sanity checks
    //==========================================================
    initial begin
        if (BALANCE_WIDTH < PRICE_WIDTH) begin
            $error("BALANCE_WIDTH must be >= PRICE_WIDTH");
        end

        if (BALANCE_WIDTH < COIN_WIDTH) begin
            $error("BALANCE_WIDTH must be >= COIN_WIDTH");
        end
    end

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
    // Transaction registers
    //==========================================================

    // Inserted money
    logic [BALANCE_WIDTH-1:0] balance_reg;

    // Price captured when item is selected
    logic [PRICE_WIDTH-1:0] selected_price_reg;

    // Stock captured when item is selected
    logic selected_stock_reg;

    // Calculated change
    logic [PRICE_WIDTH-1:0] change_reg;

    //==========================================================
    // Extended arithmetic operands
    //==========================================================
    logic [BALANCE_WIDTH-1:0] coin_extended;
    logic [BALANCE_WIDTH-1:0] price_extended;

    // One additional bit detects overflow.
    logic [BALANCE_WIDTH:0] balance_sum;

    //==========================================================
    // Maximum representable balance
    //==========================================================
    localparam logic [BALANCE_WIDTH-1:0] MAX_BALANCE =
        {BALANCE_WIDTH{1'b1}};

    //==========================================================
    // Width-safe zero extension
    //==========================================================
    always_comb begin

        coin_extended = '0;
        price_extended = '0;

        coin_extended[COIN_WIDTH-1:0] =
            coin_value;

        price_extended[PRICE_WIDTH-1:0] =
            selected_price_reg;

    end

    //==========================================================
    // Balance addition
    //==========================================================
    always_comb begin

        balance_sum =
            {1'b0, balance_reg} +
            {1'b0, coin_extended};

    end

    //==========================================================
    // 1. STATE REGISTER
    //
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

            balance_reg       <= '0;
            selected_price_reg <= '0;
            selected_stock_reg <= 1'b0;
            change_reg         <= '0;

        end
        else begin

            //==================================================
            // COIN ACCUMULATION
            // Only IDLE and COIN_INSERTED accept coins.
            //==================================================
            if (coin_valid &&
                ((state == IDLE) ||
                 (state == COIN_INSERTED))) begin

                // Saturate instead of wrapping around.
                if (balance_sum[BALANCE_WIDTH])
                    balance_reg <= MAX_BALANCE;
                else
                    balance_reg <= balance_sum[BALANCE_WIDTH-1:0];

            end

            //==================================================
            // LATCH ITEM INFORMATION
            //
            // Selection occurs only after sufficient balance.
            //==================================================
            if ((state == COIN_INSERTED) &&
                item_select &&
                (balance_reg >= price_extended)) begin

                selected_price_reg <= item_price;
                selected_stock_reg <= stock_available;

            end

            //==================================================
            // CALCULATE CHANGE
            //
            // Only an in-stock item with sufficient balance
            // can generate change.
            //==================================================
            if ((state == ITEM_SELECTED) &&
                selected_stock_reg &&
                (balance_reg >= price_extended)) begin

                change_reg <=
                    balance_reg[PRICE_WIDTH-1:0] -
                    selected_price_reg;

            end

            //==================================================
            // CLEAR TRANSACTION AFTER CHANGE
            //==================================================
            if (state == CHANGE_RETURN) begin

                balance_reg        <= '0;
                change_reg         <= '0;
                selected_price_reg <= '0;
                selected_stock_reg <= 1'b0;

            end

            //==================================================
            // CLEAR TRANSACTION AFTER REFUND
            //==================================================
            if (state == OUT_OF_STOCK_ERR) begin

                balance_reg        <= '0;
                change_reg         <= '0;
                selected_price_reg <= '0;
                selected_stock_reg <= 1'b0;

            end

            //==================================================
            // EXACT PAYMENT
            //
            // No change is required.
            //==================================================
            if ((state == DISPENSING) &&
                (balance_reg == price_extended)) begin

                balance_reg        <= '0;
                change_reg         <= '0;
                selected_price_reg <= '0;
                selected_stock_reg <= 1'b0;

            end

        end

    end

    //==========================================================
    // 3. NEXT-STATE LOGIC
    //==========================================================
    always_comb begin

        // Default prevents inferred latches.
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
            // Insufficient balance:
            // stay here and wait for additional coins.
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

                // Stock check has highest priority.
                if (!selected_stock_reg) begin

                    next_state = OUT_OF_STOCK_ERR;

                end

                // Defensive check for insufficient balance.
                else if (balance_reg < price_extended) begin

                    next_state = COIN_INSERTED;

                end

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
            // Illegal state recovery
            //==================================================
            default: begin

                next_state = IDLE;

            end

        endcase

    end

    //==========================================================
    // 4. OUTPUT LOGIC
    //
    // Moore-style FSM outputs plus hard safety interlock.
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
            //
            // Refund complete inserted balance.
            //==================================================
            OUT_OF_STOCK_ERR: begin

                error = 1'b1;

                change_amount =
                    balance_reg[PRICE_WIDTH-1:0];

            end

            default: begin

                dispense_item = 1'b0;
                change_amount = '0;
                error         = 1'b0;

            end

        endcase

        //======================================================
        // HARDWARE SAFETY INTERLOCK
        //
        // This is independent of the FSM state.
        // Even if the FSM somehow reaches DISPENSING while
        // stock_available is LOW, the physical dispense command
        // is forced LOW.
        //======================================================
        if (!stock_available)
            dispense_item = 1'b0;

    end

    //==========================================================
    // Balance output
    //==========================================================
    assign balance = balance_reg;

endmodule
