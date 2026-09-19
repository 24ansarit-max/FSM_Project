
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

    output reg [1:0] dispense_item,
    output reg       dispense_valid,
    output reg [7:0] change_amount,
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
    localparam ERROR         = 3'b101;

    reg [2:0] state;
    reg [2:0] next_state;

    // Total value of coins inserted
    reg [7:0] total_credit;

    // Store the selected item during the transaction
    reg [1:0] selected_item;

    // Price of the selected item
    reg [7:0] selected_price;

    // ------------------------------------------------------------
    // Item price lookup
    // ------------------------------------------------------------
    function [7:0] get_price;
        input [1:0] item_code_in;

        begin
            case (item_code_in)
                2'b00: get_price = PRICE_0;
                2'b01: get_price = PRICE_1;
                2'b10: get_price = PRICE_2;
                2'b11: get_price = PRICE_3;
                default: get_price = 8'd0;
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // State register and data registers
    // Synchronous active-high reset
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            total_credit  <= 8'd0;
            selected_item <= 2'b00;
            selected_price <= 8'd0;
        end
        else begin
            state <= next_state;

            case (state)

                // ------------------------------------------------
                // IDLE:
                // Accept the first coin and begin a transaction.
                // ------------------------------------------------
                IDLE: begin
                    if (coin_insert) begin
                        total_credit <= coin_value;
                    end
                end

                // ------------------------------------------------
                // COIN_INSERTED:
                // Accumulate additional coins or accept selection.
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
                // Availability and sufficient-credit checks are
                // performed by the next-state logic.
                // ------------------------------------------------
                ITEM_SELECTED: begin
                    // No register update required.
                end

                // ------------------------------------------------
                // DISPENSING:
                // Item is dispensed. Change was calculated by
                // the output logic.
                // ------------------------------------------------
                DISPENSING: begin
                    // No register update required.
                end

                // ------------------------------------------------
                // CHANGE_RETURN:
                // Change has been held for one cycle.
                // Clear the transaction credit.
                // ------------------------------------------------
                CHANGE_RETURN: begin
                    total_credit <= 8'd0;
                end

                // ------------------------------------------------
                // ERROR:
                // Sold-out/invalid selection. Full credit is
                // refunded without dispensing an item.
                // ------------------------------------------------
                ERROR: begin
                    total_credit <= 8'd0;
                end

                // Safe recovery
                default: begin
                    state        <= IDLE;
                    total_credit <= 8'd0;
                end

            endcase
        end
    end

    // ------------------------------------------------------------
    // Next-state combinational logic
    // ------------------------------------------------------------
    always @(*) begin
        // Default: remain in current state
        next_state = state;

        case (state)

            // IDLE -> COIN_INSERTED when a coin arrives
            IDLE: begin
                if (coin_insert)
                    next_state = COIN_INSERTED;
            end

            // Wait for selection or more coins
            COIN_INSERTED: begin
                if (select_item)
                    next_state = ITEM_SELECTED;
            end

            // Check stock first, then check available credit
            ITEM_SELECTED: begin

                // Sold out: go to ERROR and refund all credit
                if (!item_available[selected_item]) begin
                    next_state = ERROR;
                end

                // Insufficient coins: keep existing credit and
                // return to COIN_INSERTED to accept more coins
                else if (total_credit < selected_price) begin
                    next_state = COIN_INSERTED;
                end

                // Enough credit and item is available
                else begin
                    next_state = DISPENSING;
                end
            end

            // Dispensing lasts one clock cycle
            DISPENSING: begin
                next_state = CHANGE_RETURN;
            end

            // Hold change for one clock cycle, then finish
            CHANGE_RETURN: begin
                next_state = IDLE;
            end

            // Refund full credit for an unavailable/invalid item
            ERROR: begin
                next_state = IDLE;
            end

            // Safe recovery from an invalid state
            default: begin
                next_state = IDLE;
            end

        endcase
    end

    // ------------------------------------------------------------
    // Output combinational logic
    // ------------------------------------------------------------
    always @(*) begin

        // Default outputs prevent latches
        dispense_item  = 2'b00;
        dispense_valid = 1'b0;
        change_amount   = 8'd0;
        error           = 1'b0;
        ready           = 1'b0;

        case (state)

            // Machine is ready to accept coins
            IDLE: begin
                ready = 1'b1;
            end

            // Waiting for selection or additional coins
            COIN_INSERTED: begin
                ready = 1'b0;
            end

            // Checking item availability and credit
            ITEM_SELECTED: begin
                ready = 1'b0;
            end

            // Dispense selected item and calculate change
            DISPENSING: begin
                dispense_valid = 1'b1;
                dispense_item  = selected_item;
                change_amount   = total_credit - selected_price;
            end

            // Hold change output for one clock cycle
            CHANGE_RETURN: begin
                change_amount = total_credit - selected_price;
            end

            // Sold-out/invalid selection:
            // refund the complete accumulated credit
            ERROR: begin
                error         = 1'b1;
                change_amount = total_credit;
            end

            // Safe default
            default: begin
                dispense_item  = 2'b00;
                dispense_valid = 1'b0;
                change_amount   = 8'd0;
                error           = 1'b1;
                ready           = 1'b0;
            end

        endcase
    end

endmodule
