`timescale 1ns/1ps

module vending_machine #(
    parameter int WIDTH = 8
)(
    input  logic             clk,
    input  logic             rst,

    // Coin interface
    input  logic             coin_valid,
    input  logic [WIDTH-1:0] coin_value,

    // Item interface
    input  logic             item_select,
    input  logic [WIDTH-1:0] item_price,
    input  logic             stock_available,

    // Outputs
    output logic             dispense,
    output logic [WIDTH-1:0] change_amount,
    output logic             error
);

    //==========================================================
    // FSM states
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
    // Transaction registers
    //==========================================================
    logic [WIDTH-1:0] total_amount;
    logic [WIDTH-1:0] change_reg;

    //==========================================================
    // Sequential logic
    //==========================================================
    always_ff @(posedge clk) begin

        if (rst) begin
            state        <= IDLE;
            total_amount <= '0;
            change_reg   <= '0;
        end
        else begin

            // State update
            state <= next_state;

            // Accumulate coins
            if (coin_valid &&
                (state == IDLE || state == COIN_INSERTED)) begin

                total_amount <= total_amount + coin_value;
            end

            // Calculate change
            if (state == ITEM_SELECTED &&
                stock_available &&
                (total_amount >= item_price)) begin

                change_reg <= total_amount - item_price;
            end

            // Clear completed transaction
            if (state == CHANGE_RETURN) begin
                total_amount <= '0;
                change_reg   <= '0;
            end

            // Clear refunded transaction
            if (state == OUT_OF_STOCK_ERROR) begin
                total_amount <= '0;
                change_reg   <= '0;
            end

        end
    end

    //==========================================================
    // Next-state logic
    //==========================================================
    always_comb begin

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
            //==================================================
            COIN_INSERTED: begin

                if (item_select &&
                    (total_amount >= item_price)) begin

                    next_state = ITEM_SELECTED;
                end

            end

            //==================================================
            // ITEM SELECTED
            //==================================================
            ITEM_SELECTED: begin

                if (!stock_available) begin
                    next_state = OUT_OF_STOCK_ERROR;
                end
                else if (total_amount < item_price) begin
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

                if (total_amount > item_price)
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
            OUT_OF_STOCK_ERROR: begin

                next_state = IDLE;

            end

            //==================================================
            // Illegal-state recovery
            //==================================================
            default: begin

                next_state = IDLE;

            end

        endcase

    end

    //==========================================================
    // Moore output logic
    //==========================================================
    always_comb begin

        // Default outputs
        dispense      = 1'b0;
        change_amount  = '0;
        error          = 1'b0;

        case (state)

            // Dispense item
            DISPENSING: begin
                dispense = 1'b1;
            end

            // Return calculated change
            CHANGE_RETURN: begin
                change_amount = change_reg;
            end

            // Out-of-stock: refund complete balance
            OUT_OF_STOCK_ERROR: begin
                error = 1'b1;
                change_amount = total_amount;
            end

            default: begin
                dispense      = 1'b0;
                change_amount = '0;
                error         = 1'b0;
            end

        endcase

    end

endmodule
