
module vending_machine_controller #(
    parameter [7:0] PRICE_0 = 8'd10,
    parameter [7:0] PRICE_1 = 8'd20,
    parameter [7:0] PRICE_2 = 8'd30,
    parameter [7:0] PRICE_3 = 8'd40
)(
    input clk,
    input reset,

    input       coin_insert,
    input [7:0] coin_value,

    input       select_item,
    input [1:0] item_code,

    input [3:0] item_available,

    output reg       dispense_valid,
    output reg [1:0] dispense_item,
    output reg [7:0] change_amount,
    output reg       error,
    output reg       ready
);

    // ============================================================
    // FSM state encoding
    // ============================================================
    localparam IDLE          = 3'b000;
    localparam COIN_INSERTED = 3'b001;
    localparam ITEM_SELECTED = 3'b010;
    localparam DISPENSING    = 3'b011;
    localparam CHANGE_RETURN = 3'b100;
    localparam OUT_OF_STOCK  = 3'b101;

    reg [2:0] state;
    reg [2:0] next_state;

    // Accumulated value of all inserted coins
    reg [7:0] total_credit;

    // Latched item selection and price
    reg [1:0] selected_item;
    reg [7:0] selected_price;

    // ============================================================
    // Item price lookup
    // Four items have configurable prices.
    // ============================================================
    function [7:0] get_price;
        input [1:0] item;
        begin
            case (item)
                2'b00: get_price = PRICE_0;
                2'b01: get_price = PRICE_1;
                2'b10: get_price = PRICE_2;
                2'b11: get_price = PRICE_3;
                default: get_price = 8'd0;
            endcase
        end
    endfunction

    // ============================================================
    // State register and transaction data
    // Synchronous active-high reset
    // ============================================================
    always @(posedge clk) begin
        if (reset) begin
            state          <= IDLE;
            total_credit   <= 8'd0;
            selected_item  <= 2'b00;
            selected_price <= 8'd0;
        end
        else begin
            state <= next_state;

            case (state)

                // ------------------------------------------------
                // IDLE:
                // Wait for the first coin.
                // ------------------------------------------------
                IDLE: begin
                    if (coin_insert) begin
                        total_credit <= coin_value;
                    end
                end

                // ------------------------------------------------
                // COIN_INSERTED:
                // Accept additional coins and accumulate credit.
                // A selection moves the FSM to ITEM_SELECTED.
                // ------------------------------------------------
                COIN_INSERTED: begin
                    if (coin_insert) begin
                        total_credit <= total_credit + coin_value;
                    end

                    if (select_item) begin
                        selected_item  <= item_code;
                        selected_price <= get_price(item_code);
                    end
                end

                // ------------------------------------------------
                // ITEM_SELECTED:
                // Stock and credit checks are performed in the
                // next-state logic.
                // ------------------------------------------------
                ITEM_SELECTED: begin
                    // No data update required.
                end

                // ------------------------------------------------
                // DISPENSING:
                // The selected item is dispensed for one cycle.
                // ------------------------------------------------
                DISPENSING: begin
                    // No data update required.
                end

                // ------------------------------------------------
                // CHANGE_RETURN:
                // Change is available for one cycle.
                // Credit is cleared after the transaction.
                // ------------------------------------------------
                CHANGE_RETURN: begin
                    total_credit <= 8'd0;
                end

                // ------------------------------------------------
                // OUT_OF_STOCK:
                // Full inserted credit is refunded.
                // Credit is cleared after the refund.
                // ------------------------------------------------
                OUT_OF_STOCK: begin
                    total_credit <= 8'd0;
                end

                // Safe recovery from an invalid state
                default: begin
                    state        <= IDLE;
                    total_credit <= 8'd0;
                end

            endcase
        end
    end

    // ============================================================
    // Next-state combinational logic
    // ============================================================
    always @(*) begin
        // Default: stay in the current state
        next_state = state;

        case (state)

            // ------------------------------------------------
            // IDLE -> COIN_INSERTED when a coin is inserted.
            // ------------------------------------------------
            IDLE: begin
                if (coin_insert)
                    next_state = COIN_INSERTED;
            end

            // ------------------------------------------------
            // COIN_INSERTED:
            // Continue accepting coins or process a selection.
            // ------------------------------------------------
            COIN_INSERTED: begin
                if (select_item)
                    next_state = ITEM_SELECTED;
                else
                    next_state = COIN_INSERTED;
            end

            // ------------------------------------------------
            // ITEM_SELECTED:
            // 1. Sold out -> OUT_OF_STOCK and refund.
            // 2. Insufficient credit -> COIN_INSERTED.
            //    Existing credit is NOT cleared.
            // 3. Enough credit -> DISPENSING.
            // ------------------------------------------------
            ITEM_SELECTED: begin
                if (!item_available[selected_item]) begin
                    next_state = OUT_OF_STOCK;
                end
                else if (total_credit < selected_price) begin
                    // Insufficient coins:
                    // keep total_credit and wait for more coins.
                    next_state = COIN_INSERTED;
                end
                else begin
                    // Item available and sufficient payment.
                    next_state = DISPENSING;
                end
            end

            // ------------------------------------------------
            // DISPENSING:
            // Dispense item and then return any change.
            // ------------------------------------------------
            DISPENSING: begin
                next_state = CHANGE_RETURN;
            end

            // ------------------------------------------------
            // CHANGE_RETURN:
            // Hold change output for one cycle, then finish.
            // ------------------------------------------------
            CHANGE_RETURN: begin
                next_state = IDLE;
            end

            // ------------------------------------------------
            // OUT_OF_STOCK:
            // Refund the complete inserted credit.
            // No item is dispensed.
            // ------------------------------------------------
            OUT_OF_STOCK: begin
                next_state = IDLE;
            end

            // Safe recovery
            default: begin
                next_state = IDLE;
            end

        endcase
    end

    // ============================================================
    // Output combinational logic
    // ============================================================
    always @(*) begin

        // Default values prevent latches
        dispense_valid = 1'b0;
        dispense_item  = 2'b00;
        change_amount   = 8'd0;
        error           = 1'b0;
        ready           = 1'b0;

        case (state)

            // ------------------------------------------------
            // IDLE:
            // Machine is ready to accept coins.
            // ------------------------------------------------
            IDLE: begin
                ready = 1'b1;
            end

            // ------------------------------------------------
            // COIN_INSERTED:
            // Waiting for item selection or more coins.
            // ------------------------------------------------
            COIN_INSERTED: begin
                ready = 1'b0;
            end

            // ------------------------------------------------
            // ITEM_SELECTED:
            // Selection is being checked.
            // ------------------------------------------------
            ITEM_SELECTED: begin
                ready = 1'b0;
            end

            // ------------------------------------------------
            // DISPENSING:
            // Assert dispense_valid and identify the item.
            // Calculate change = credit - item price.
            // ------------------------------------------------
            DISPENSING: begin
                dispense_valid = 1'b1;
                dispense_item  = selected_item;
                change_amount   = total_credit - selected_price;
            end

            // ------------------------------------------------
            // CHANGE_RETURN:
            // Hold the calculated change for one clock cycle.
            // ------------------------------------------------
            CHANGE_RETURN: begin
                change_amount = total_credit - selected_price;
            end

            // ------------------------------------------------
            // OUT_OF_STOCK:
            // Assert error and refund ALL inserted credit.
            // No dispensing occurs in this state.
            // ------------------------------------------------
            OUT_OF_STOCK: begin
                error         = 1'b1;
                change_amount = total_credit;
            end

            // Safe default
            default: begin
                dispense_valid = 1'b0;
                dispense_item  = 2'b00;
                change_amount   = 8'd0;
                error           = 1'b1;
                ready           = 1'b0;
            end

        endcase
    end

endmodule
