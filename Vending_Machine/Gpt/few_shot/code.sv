module vending_machine_controller (
    input clk,
    input reset,

    // Coin input
    input       coin_in,
    input [7:0] coin_value,

    // Item selection
    input       item_select_valid,
    input [1:0] item_select,

    // Stock availability for 4 items
    input [3:0] item_available,

    // Outputs
    output reg       dispense,
    output reg [15:0] change_amount,
    output reg       error,
    output reg       ready
);

    // ------------------------------------------------------------
    // State encoding
    // ------------------------------------------------------------
    localparam IDLE          = 3'b000;
    localparam COIN_INSERTED = 3'b001;
    localparam ITEM_SELECTED = 3'b010;
    localparam DISPENSING    = 3'b011;
    localparam CHANGE_RETURN = 3'b100;
    localparam OUT_OF_STOCK  = 3'b101;

    reg [2:0] state;
    reg [2:0] next_state;

    // Accumulated inserted coin value
    reg [15:0] balance;

    // Selected item and its price
    reg [1:0] selected_item;
    reg [7:0] selected_price;

    // ------------------------------------------------------------
    // Item price lookup
    // Item 0 = 10, Item 1 = 20, Item 2 = 30, Item 3 = 40
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // State register and accumulated coin logic
    // Synchronous active-high reset
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            balance       <= 16'd0;
            selected_item <= 2'b00;
            selected_price <= 8'd0;
        end
        else begin
            state <= next_state;

            case (state)

                // Wait for the first coin
                IDLE: begin
                    if (coin_in) begin
                        balance <= coin_value;
                    end
                end

                // Accumulate additional coins
                COIN_INSERTED: begin
                    if (coin_in) begin
                        balance <= balance + coin_value;
                    end

                    // Store selected item and its price
                    if (item_select_valid) begin
                        selected_item  <= item_select;
                        selected_price <= get_price(item_select);
                    end
                end

                // Selection has been stored; no balance change here
                ITEM_SELECTED: begin
                    // Decision is handled by next-state logic
                end

                // Dispensing is one FSM cycle
                DISPENSING: begin
                    // Item is dispensed
                end

                // Change is returned, then transaction ends
                CHANGE_RETURN: begin
                    balance <= 16'd0;
                end

                // Refund inserted coins and end transaction
                OUT_OF_STOCK: begin
                    balance <= 16'd0;
                end

                default: begin
                    state   <= IDLE;
                    balance <= 16'd0;
                end

            endcase
        end
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always @(*) begin

        // Default: remain in current state
        next_state = state;

        case (state)

            // ----------------------------------------------------
            // IDLE: Wait for a coin
            // ----------------------------------------------------
            IDLE: begin
                if (coin_in)
                    next_state = COIN_INSERTED;
            end

            // ----------------------------------------------------
            // COIN_INSERTED: Wait for item selection.
            // More coins can also be inserted.
            // ----------------------------------------------------
            COIN_INSERTED: begin
                if (item_select_valid)
                    next_state = ITEM_SELECTED;
            end

            // ----------------------------------------------------
            // ITEM_SELECTED:
            // Check stock first, then check payment.
            // ----------------------------------------------------
            ITEM_SELECTED: begin

                // Sold out -> error and refund
                if (!item_available[selected_item])
                    next_state = OUT_OF_STOCK;

                // Insufficient balance -> wait for more coins
                else if (balance < selected_price)
                    next_state = COIN_INSERTED;

                // Sufficient balance and item available
                else
                    next_state = DISPENSING;
            end

            // ----------------------------------------------------
            // DISPENSING: Item is dispensed for one cycle
            // ----------------------------------------------------
            DISPENSING: begin
                if (balance > selected_price)
                    next_state = CHANGE_RETURN;
                else
                    next_state = IDLE;
            end

            // ----------------------------------------------------
            // CHANGE_RETURN: Return remaining balance
            // ----------------------------------------------------
            CHANGE_RETURN: begin
                next_state = IDLE;
            end

            // ----------------------------------------------------
            // OUT_OF_STOCK: Refund coins, then return to IDLE
            // ----------------------------------------------------
            OUT_OF_STOCK: begin
                next_state = IDLE;
            end

            // Safe recovery
            default: begin
                next_state = IDLE;
            end

        endcase
    end

    // ------------------------------------------------------------
    // Output logic
    // ------------------------------------------------------------
    always @(*) begin

        // Default outputs
        dispense      = 1'b0;
        change_amount  = 16'd0;
        error         = 1'b0;
        ready         = 1'b0;

        case (state)

            // Machine ready for a new transaction
            IDLE: begin
                ready = 1'b1;
            end

            // Waiting for selection or additional coins
            COIN_INSERTED: begin
                ready = 1'b0;
            end

            // Checking item selection and payment
            ITEM_SELECTED: begin
                ready = 1'b0;
            end

            // Dispense selected item
            DISPENSING: begin
                dispense = 1'b1;

                if (balance > selected_price)
                    change_amount = balance - selected_price;
                else
                    change_amount = 16'd0;
            end

            // Return remaining money
            CHANGE_RETURN: begin
                change_amount = balance - selected_price;
            end

            // Sold-out item: refund complete balance and assert error
            OUT_OF_STOCK: begin
                error         = 1'b1;
                change_amount = balance;
            end

            // Safe default outputs
            default: begin
                dispense      = 1'b0;
                change_amount = 16'd0;
                error         = 1'b1;
                ready         = 1'b0;
            end

        endcase
    end

endmodule
