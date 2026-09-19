module vending_machine_controller (
    input clk,
    input reset,

    // Coin input
    input       coin_in,
    input [7:0] coin_value,

    // Item selection
    input       item_select_valid,
    input [1:0] item_select,

    // Availability of 4 items
    input [3:0] item_available,

    // Outputs
    output reg        dispense,
    output reg [15:0] change_amount,
    output reg        error,
    output reg        ready
);

    // ============================================================
    // State encoding
    // ============================================================
    localparam IDLE          = 3'b000;
    localparam COIN_INSERTED = 3'b001;
    localparam ITEM_SELECTED = 3'b010;
    localparam DISPENSING    = 3'b011;
    localparam CHANGE_RETURN = 3'b100;
    localparam OUT_OF_STOCK  = 3'b101;

    reg [2:0] state;
    reg [2:0] next_state;

    // Accumulated value of inserted coins
    reg [15:0] balance;

    // Currently selected item and its price
    reg [1:0] selected_item;
    reg [7:0] selected_price;

    // ============================================================
    // Item price lookup
    // Item 0 = 10
    // Item 1 = 20
    // Item 2 = 30
    // Item 3 = 40
    // ============================================================
    function [7:0] get_price;
        input [1:0] item;

        begin
            case (item)
                2'b00: get_price = 8'd10;
                2'b01: get_price = 8'd20;
                2'b10: get_price = 8'd30;
                2'b11: get_price = 8'd40;
                default: get_price = 8'd0;
            endcase
        end
    endfunction

    // ============================================================
    // State register and data registers
    // Synchronous active-high reset
    // ============================================================
    always @(posedge clk) begin

        if (reset) begin
            state          <= IDLE;
            balance        <= 16'd0;
            selected_item  <= 2'b00;
            selected_price <= 8'd0;
        end

        else begin
            state <= next_state;

            case (state)

                // ------------------------------------------------
                // IDLE
                // Wait for the first coin.
                // ------------------------------------------------
                IDLE: begin
                    if (coin_in) begin
                        balance <= coin_value;
                    end
                end

                // ------------------------------------------------
                // COIN_INSERTED
                // Accumulate additional coins.
                // Selection can be made when ready.
                // ------------------------------------------------
                COIN_INSERTED: begin

                    if (coin_in) begin
                        balance <= balance + coin_value;
                    end

                    if (item_select_valid) begin
                        selected_item  <= item_select;
                        selected_price <= get_price(item_select);
                    end
                end

                // ------------------------------------------------
                // ITEM_SELECTED
                // Next-state logic checks stock and balance.
                // ------------------------------------------------
                ITEM_SELECTED: begin
                    // No data update required here.
                end

                // ------------------------------------------------
                // DISPENSING
                // The output logic asserts dispense for this state.
                // ------------------------------------------------
                DISPENSING: begin
                    // Item is dispensed.
                end

                // ------------------------------------------------
                // CHANGE_RETURN
                // Return balance - item price.
                // Clear balance after returning change.
                // ------------------------------------------------
                CHANGE_RETURN: begin
                    balance <= 16'd0;
                end

                // ------------------------------------------------
                // OUT_OF_STOCK
                // Refund the complete inserted balance.
                // No item is dispensed.
                // ------------------------------------------------
                OUT_OF_STOCK: begin
                    balance <= 16'd0;
                end

                // ------------------------------------------------
                // Safe recovery from an invalid state
                // ------------------------------------------------
                default: begin
                    state   <= IDLE;
                    balance <= 16'd0;
                end

            endcase
        end
    end

    // ============================================================
    // Next-state combinational logic
    // ============================================================
    always @(*) begin

        // By default, remain in the current state
        next_state = state;

        case (state)

            // ------------------------------------------------
            // IDLE -> COIN_INSERTED when a coin arrives
            // ------------------------------------------------
            IDLE: begin
                if (coin_in)
                    next_state = COIN_INSERTED;
            end

            // ------------------------------------------------
            // Wait for a valid item selection
            // Additional coins are handled in the state register.
            // ------------------------------------------------
            COIN_INSERTED: begin
                if (item_select_valid)
                    next_state = ITEM_SELECTED;
            end

            // ------------------------------------------------
            // Check stock first, then check available balance.
            // ------------------------------------------------
            ITEM_SELECTED: begin

                // Sold out:
                // Go to error/refund state.
                if (!item_available[selected_item]) begin
                    next_state = OUT_OF_STOCK;
                end

                // Insufficient money:
                // Return to COIN_INSERTED and keep balance.
                else if (balance < selected_price) begin
                    next_state = COIN_INSERTED;
                end

                // Enough money and item available:
                // Dispense the item.
                else begin
                    next_state = DISPENSING;
                end
            end

            // ------------------------------------------------
            // Dispensing lasts one clock cycle.
            // If there is change, return it.
            // Otherwise go directly to IDLE.
            // ------------------------------------------------
            DISPENSING: begin
                if (balance > selected_price)
                    next_state = CHANGE_RETURN;
                else
                    next_state = IDLE;
            end

            // ------------------------------------------------
            // Return the calculated change.
            // ------------------------------------------------
            CHANGE_RETURN: begin
                next_state = IDLE;
            end

            // ------------------------------------------------
            // Refund the complete balance for a sold-out item.
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

        // Default outputs prevent latches
        dispense      = 1'b0;
        change_amount  = 16'd0;
        error         = 1'b0;
        ready         = 1'b0;

        case (state)

            // ------------------------------------------------
            // Machine is ready for a new transaction
            // ------------------------------------------------
            IDLE: begin
                ready = 1'b1;
            end

            // ------------------------------------------------
            // Waiting for item selection or additional coins
            // ------------------------------------------------
            COIN_INSERTED: begin
                ready = 1'b0;
            end

            // ------------------------------------------------
            // Item and payment are being checked
            // ------------------------------------------------
            ITEM_SELECTED: begin
                ready = 1'b0;
            end

            // ------------------------------------------------
            // Dispense selected item
            // ------------------------------------------------
            DISPENSING: begin
                dispense = 1'b1;

                if (balance > selected_price)
                    change_amount = balance - selected_price;
                else
                    change_amount = 16'd0;
            end

            // ------------------------------------------------
            // Return remaining money
            // ------------------------------------------------
            CHANGE_RETURN: begin
                change_amount = balance - selected_price;
            end

            // ------------------------------------------------
            // Sold-out item:
            // Signal error and refund complete balance.
            // ------------------------------------------------
            OUT_OF_STOCK: begin
                error         = 1'b1;
                change_amount = balance;
            end

            // Safe output defaults
            default: begin
                dispense      = 1'b0;
                change_amount = 16'd0;
                error         = 1'b1;
                ready         = 1'b0;
            end

        endcase
    end

endmodule
