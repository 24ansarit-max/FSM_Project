`timescale 1ns/1ps

module vending_machine #(
    parameter int WIDTH = 8
)(
    input  logic             clk,
    input  logic             rst,

    //==========================================================
    // Coin interface
    //==========================================================
    input  logic             coin_valid,
    input  logic [WIDTH-1:0] coin_value,       // 1, 2, 5, 10

    //==========================================================
    // Item interface
    //==========================================================
    input  logic             item_select,
    input  logic [WIDTH-1:0] item_price,
    input  logic             stock_available,

    //==========================================================
    // Outputs
    //==========================================================
    output logic             dispense,
    output logic [WIDTH-1:0] change_amount,
    output logic             error
);

    //==========================================================
    // FSM state definition
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
    // State register + accumulator
    //==========================================================
    always_ff @(posedge clk) begin

        if (rst) begin
            state        <= IDLE;
            total_amount <= '0;
            change_reg   <= '0;
        end

        else begin
            state <= next_state;

            //--------------------------------------------------
            // Coin accumulator
            //--------------------------------------------------
            if (coin_valid &&
                (state == IDLE || state == COIN_INSERTED)) begin

                total_amount <= total_amount + coin_value;
            end

            //--------------------------------------------------
            // Calculate change when item is selected
            //--------------------------------------------------
            if (state == ITEM_SELECTED &&
                stock_available &&
                (total_amount >= item_price)) begin

                change_reg <= total_amount - item_price;
            end

            //--------------------------------------------------
            // Clear transaction after change return
            //--------------------------------------------------
            if (state == CHANGE_RETURN) begin
                total_amount <= '0;
                change_reg   <= '0;
            end

            //--------------------------------------------------
            // Clear transaction after refund
            //--------------------------------------------------
            if (state == OUT_OF_STOCK_ERROR) begin
                total_amount <= '0;
                change_reg   <= '0;
            end

        end
    end

    //==========================================================
    // Next-state combinational logic
    //==========================================================
    always_comb begin

        // Default: remain in current state
        next_state = state;

        case (state)

            //--------------------------------------------------
            // IDLE
            //--------------------------------------------------
            IDLE: begin

                if (coin_valid)
                    next_state = COIN_INSERTED;

            end

            //--------------------------------------------------
            // COIN INSERTED
            //--------------------------------------------------
            COIN_INSERTED: begin

                // Item can only be selected with sufficient
                // accumulated balance.
                if (item_select &&
                    (total_amount >= item_price)) begin

                    next_state = ITEM_SELECTED;
                end

            end

            //--------------------------------------------------
            // ITEM SELECTED
            //--------------------------------------------------
            ITEM_SELECTED: begin

                // Item unavailable -> refund
                if (!stock_available) begin

                    next_state = OUT_OF_STOCK_ERROR;
                end

                // Defensive check for insufficient balance
                else if (total_amount < item_price) begin

                    next_state = COIN_INSERTED;
                end

                // Valid transaction
                else begin

                    next_state = DISPENSING;
                end

            end

            //--------------------------------------------------
            // DISPENSING
            //--------------------------------------------------
            DISPENSING: begin

                // Overpayment -> return change
                if (total_amount > item_price)
                    next_state = CHANGE_RETURN;

                // Exact payment -> transaction complete
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
            // Safety recovery
            //--------------------------------------------------
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

            //--------------------------------------------------
            // Dispense item
            //--------------------------------------------------
            DISPENSING: begin

                dispense = 1'b1;

            end

            //--------------------------------------------------
            // Return change
            //--------------------------------------------------
            CHANGE_RETURN: begin

                change_amount = change_reg;

            end

            //--------------------------------------------------
            // Out-of-stock / error
            //--------------------------------------------------
            OUT_OF_STOCK_ERROR: begin

                error = 1'b1;

                // Refund complete inserted amount
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
