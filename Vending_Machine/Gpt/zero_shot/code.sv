module vending_machine_controller #(
    parameter BALANCE_WIDTH = 16,
    parameter PRICE_WIDTH   = 8
)(
    input  clk,
    input reset,

    // Coin input
    input coin_in,
    input [7:0] coin_value,

    // Item selection: 2-bit code for 4 items
    input [1:0] item_select,

    // Availability of 4 items
    // item_available[0] -> Item 0
    // item_available[1] -> Item 1
    // item_available[2] -> Item 2
    // item_available[3] -> Item 3
    input [3:0] item_available,

    // Outputs
    output reg dispense,
    output reg [BALANCE_WIDTH-1:0] change_amount,
    output reg error,
    output reg ready
);

    // ------------------------------------------------------------
    // State encoding
    // ------------------------------------------------------------
    localparam IDLE          = 3'b000;
    localparam COIN_INSERTED = 3'b001;
    localparam ITEM_SELECTED = 3'b010;
    localparam DISPENSING    = 3'b011;
    localparam CHANGE_RETURN = 3'b100;
    localparam OUT_OF_STOCK   = 3'b101;

    reg [2:0] state;

    // Stores total value of coins inserted
    reg [BALANCE_WIDTH-1:0] balance;

    // Stores selected item's price
    reg [PRICE_WIDTH-1:0] selected_price;

    // Stores selected item code
    reg [1:0] selected_item;

    // ------------------------------------------------------------
    // Item price lookup
    // Four items have different fixed prices.
    // ------------------------------------------------------------
    function [PRICE_WIDTH-1:0] get_price;
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
    // State, balance and selection update logic
    // Synchronous active-high reset
    // ------------------------------------------------------------
    always @(posedge clk) begin

        if (reset) begin
            state         <= IDLE;
            balance       <= 0;
            selected_price <= 0;
            selected_item <= 0;
        end

        else begin
            case (state)

                // ------------------------------------------------
                // IDLE: Wait for a coin
                // ------------------------------------------------
                IDLE: begin
                    if (coin_in) begin
                        balance <= coin_value;
                        state   <= COIN_INSERTED;
                    end
                end

                // ------------------------------------------------
                // COIN_INSERTED: Accumulate coins and wait for
                // item selection
                // ------------------------------------------------
                COIN_INSERTED: begin

                    // Accumulate another inserted coin
                    if (coin_in) begin
                        balance <= balance + coin_value;
                    end

                    // Item selection moves to ITEM_SELECTED
                    if (item_select <= 2'b11) begin
                        selected_item  <= item_select;
                        selected_price <= get_price(item_select);
                        state          <= ITEM_SELECTED;
                    end
                end

                // ------------------------------------------------
                // ITEM_SELECTED: Check availability and balance
                // ------------------------------------------------
                ITEM_SELECTED: begin

                    // Item is sold out -> refund coins
                    if (!item_available[selected_item]) begin
                        state <= OUT_OF_STOCK;
                    end

                    // Not enough money -> return to coin state
                    else if (balance < selected_price) begin
                        state <= COIN_INSERTED;
                    end

                    // Enough money and item available
                    else begin
                        state <= DISPENSING;
                    end
                end

                // ------------------------------------------------
                // DISPENSING: Item is dispensed.
                // Change is calculated from balance - price.
                // ------------------------------------------------
                DISPENSING: begin
                    state <= CHANGE_RETURN;
                end

                // ------------------------------------------------
                // CHANGE_RETURN: Return remaining money and
                // then return to IDLE.
                // ------------------------------------------------
                CHANGE_RETURN: begin
                    balance <= 0;
                    state   <= IDLE;
                end

                // ------------------------------------------------
                // OUT_OF_STOCK: Signal error and refund all
                // inserted coins. No item is dispensed.
                // ------------------------------------------------
                OUT_OF_STOCK: begin
                    balance <= 0;
                    state   <= IDLE;
                end

                // ------------------------------------------------
                // Safe recovery from an invalid state
                // ------------------------------------------------
                default: begin
                    state   <= IDLE;
                    balance <= 0;
                end

            endcase
        end
    end

    // ------------------------------------------------------------
    // Output logic
    // ------------------------------------------------------------
    always @(*) begin

        // Default outputs
        dispense      = 1'b0;
        change_amount = 0;
        error         = 1'b0;
        ready         = 1'b0;

        case (state)

            // Machine is ready for a new transaction
            IDLE: begin
                ready = 1'b1;
            end

            // Waiting for sufficient coins or item selection
            COIN_INSERTED: begin
                ready = 1'b0;
            end

            // Checking selected item
            ITEM_SELECTED: begin
                ready = 1'b0;
            end

            // Dispense item
            DISPENSING: begin
                dispense      = 1'b1;
                change_amount = balance - selected_price;
            end

            // Return calculated change
            CHANGE_RETURN: begin
                change_amount = balance - selected_price;
            end

            // Item unavailable: signal error and refund balance
            OUT_OF_STOCK: begin
                error         = 1'b1;
                change_amount = balance;
            end

            // Safe output state
            default: begin
                dispense      = 1'b0;
                change_amount = 0;
                error         = 1'b1;
                ready         = 1'b0;
            end

        endcase
    end

endmodule
