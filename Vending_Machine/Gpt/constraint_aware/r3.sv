`timescale 1ns/1ps

module vending_machine #(
    parameter int unsigned NUM_ITEMS     = 4,
    parameter int unsigned NUM_DENOMS    = 4,
    parameter int unsigned PRICE_WIDTH   = 8,
    parameter int unsigned BALANCE_WIDTH = PRICE_WIDTH + 1,

    // Supported coin denominations
    parameter logic [PRICE_WIDTH-1:0] COIN_DENOMS [NUM_DENOMS] = '{
        8'd1, 8'd2, 8'd5, 8'd10
    }
)(
    input  logic                         clk,
    input  logic                         rst,

    //========================================================
    // Coin interface
    //========================================================
    input  logic                         coin_valid,
    input  logic [PRICE_WIDTH-1:0]       coin_value,

    //========================================================
    // Item interface
    //========================================================
    input  logic                         item_select_valid,
    input  logic [ITEM_SEL_WIDTH-1:0]    item_select,
    input  logic [PRICE_WIDTH-1:0]        item_price,
    input  logic                         item_stock,

    //========================================================
    // Controller outputs
    //========================================================
    output logic                         dispense,
    output logic [BALANCE_WIDTH-1:0]     change_amount,
    output logic                         error
);

    //========================================================
    // Safe item-select width
    //========================================================
    localparam int ITEM_SEL_WIDTH =
        (NUM_ITEMS <= 1) ? 1 : $clog2(NUM_ITEMS);

    //========================================================
    // FSM states
    //========================================================
    typedef enum logic [2:0] {
        IDLE,
        COIN_INSERTED,
        ITEM_SELECTED,
        DISPENSING,
        CHANGE_RETURN,
        OUT_OF_STOCK_ERROR
    } state_t;

    state_t state, next_state;

    //========================================================
    // Transaction registers
    //========================================================
    logic [BALANCE_WIDTH-1:0] balance_reg;
    logic [BALANCE_WIDTH-1:0] change_reg;

    //========================================================
    // Coin validation
    //========================================================
    logic coin_supported;

    integer i;

    always_comb begin
        coin_supported = 1'b0;

        for (i = 0; i < NUM_DENOMS; i = i + 1) begin
            if (coin_value == COIN_DENOMS[i])
                coin_supported = 1'b1;
        end
    end

    //========================================================
    // Extended arithmetic operands
    //========================================================
    logic [BALANCE_WIDTH-1:0] coin_ext;
    logic [BALANCE_WIDTH-1:0] price_ext;

    logic [BALANCE_WIDTH:0] balance_sum_ext;
    logic                   balance_overflow;

    always_comb begin

        coin_ext  = '0;
        price_ext = '0;

        coin_ext[PRICE_WIDTH-1:0]  = coin_value;
        price_ext[PRICE_WIDTH-1:0] = item_price;

        // Extra bit explicitly detects unsigned overflow.
        balance_sum_ext =
            {1'b0, balance_reg} +
            {1'b0, coin_ext};

        balance_overflow =
            balance_sum_ext[BALANCE_WIDTH];

    end

    //========================================================
    // 1. STATE REGISTER
    // Synchronous active-high reset
    //========================================================
    always_ff @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    //========================================================
    // 2. NEXT-STATE LOGIC
    //========================================================
    always_comb begin

        // Default prevents latch inference.
        next_state = state;

        case (state)

            //================================================
            // IDLE
            //================================================
            IDLE: begin

                if (coin_valid && coin_supported)
                    next_state = COIN_INSERTED;

            end

            //================================================
            // COIN INSERTED
            //================================================
            COIN_INSERTED: begin

                // Selection is accepted only when enough
                // money has been inserted.
                if (item_select_valid &&
                    (item_select < NUM_ITEMS) &&
                    (balance_reg >= price_ext)) begin

                    next_state = ITEM_SELECTED;

                end

            end

            //================================================
            // ITEM SELECTED
            //================================================
            ITEM_SELECTED: begin

                // IMPORTANT:
                // Out-of-stock is checked BEFORE DISPENSING.
                if (!item_stock) begin

                    next_state = OUT_OF_STOCK_ERROR;

                end
                else if (balance_reg < price_ext) begin

                    // Safety recovery if price/balance changes.
                    next_state = COIN_INSERTED;

                end
                else begin

                    next_state = DISPENSING;

                end

            end

            //================================================
            // DISPENSING
            //================================================
            DISPENSING: begin

                if (balance_reg > price_ext)
                    next_state = CHANGE_RETURN;
                else
                    next_state = IDLE;

            end

            //================================================
            // CHANGE RETURN
            //================================================
            CHANGE_RETURN: begin

                next_state = IDLE;

            end

            //================================================
            // OUT OF STOCK / ERROR
            //================================================
            OUT_OF_STOCK_ERROR: begin

                next_state = IDLE;

            end

            //================================================
            // Illegal-state recovery
            //================================================
            default: begin

                next_state = IDLE;

            end

        endcase

    end

    //========================================================
    // 3. DATA REGISTER LOGIC
    //========================================================
    always_ff @(posedge clk) begin

        if (rst) begin

            balance_reg <= '0;
            change_reg  <= '0;

        end
        else begin

            //================================================
            // Coin accumulator
            //================================================
            if (coin_valid &&
                coin_supported &&
                ((state == IDLE) ||
                 (state == COIN_INSERTED))) begin

                // Saturate instead of wrapping around.
                if (balance_overflow)
                    balance_reg <= {BALANCE_WIDTH{1'b1}};
                else
                    balance_reg <=
                        balance_sum_ext[BALANCE_WIDTH-1:0];

            end

            //================================================
            // Change calculation
            //================================================
            // Stock is verified before calculating change.
            // Since balance >= price, subtraction cannot
            // underflow.
            if ((state == ITEM_SELECTED) &&
                item_stock &&
                (balance_reg >= price_ext)) begin

                change_reg <= balance_reg - price_ext;

            end

            //================================================
            // Exact payment
            //================================================
            if ((state == DISPENSING) &&
                (balance_reg == price_ext)) begin

                balance_reg <= '0;
                change_reg  <= '0;

            end

            //================================================
            // Clear after change return
            //================================================
            if (state == CHANGE_RETURN) begin

                balance_reg <= '0;
                change_reg  <= '0;

            end

            //================================================
            // Clear after out-of-stock refund
            //================================================
            if (state == OUT_OF_STOCK_ERROR) begin

                balance_reg <= '0;
                change_reg  <= '0;

            end

        end

    end

    //========================================================
    // 4. OUTPUT LOGIC
    //========================================================
    always_comb begin

        // Default values prevent latch inference.
        dispense     = 1'b0;
        change_amount = '0;
        error         = 1'b0;

        case (state)

            //================================================
            // Dispense item
            //================================================
            DISPENSING: begin

                dispense = 1'b1;

            end

            //================================================
            // Return change
            //================================================
            CHANGE_RETURN: begin

                change_amount = change_reg;

            end

            //================================================
            // Out-of-stock / error
            //================================================
            OUT_OF_STOCK_ERROR: begin

                error = 1'b1;

                // Refund complete inserted balance.
                change_amount = balance_reg;

            end

            default: begin

                dispense      = 1'b0;
                change_amount = '0;
                error         = 1'b0;

            end

        endcase

    end

endmodule
