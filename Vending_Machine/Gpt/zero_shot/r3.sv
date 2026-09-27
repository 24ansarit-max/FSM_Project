module vending_machine #(
    parameter int WIDTH = 8
)(
    input  logic             clk,
    input  logic             reset,

    // Coin interface
    input  logic             coin_valid,
    input  logic [WIDTH-1:0] coin_value,     // 1, 2, 5, or 10

    // Item interface
    input  logic             item_select,
    input  logic [WIDTH-1:0] item_price,
    input  logic             stock_available,

    // Outputs
    output logic             dispense,
    output logic [WIDTH-1:0] change_amount,
    output logic             error
);

    typedef enum logic [2:0] {
        IDLE,
        COIN_INSERTED,
        ITEM_SELECTED,
        DISPENSING,
        CHANGE_RETURN,
        OUT_OF_STOCK_ERROR
    } state_t;

    state_t state, next_state;

    logic [WIDTH-1:0] total_amount;
    logic [WIDTH-1:0] change_reg;

    //=========================================================
    // Sequential logic
    //=========================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            state        <= IDLE;
            total_amount <= '0;
            change_reg   <= '0;
        end
        else begin
            state <= next_state;

            // Store inserted coins
            if (coin_valid &&
                (state == IDLE || state == COIN_INSERTED)) begin
                total_amount <= total_amount + coin_value;
            end

            // Calculate change when valid item is selected
            if (state == ITEM_SELECTED &&
                stock_available &&
                total_amount >= item_price) begin
                change_reg <= total_amount - item_price;
            end

            // Clear transaction after change
            if (state == CHANGE_RETURN) begin
                total_amount <= '0;
                change_reg   <= '0;
            end

            // Clear transaction after refund
            if (state == OUT_OF_STOCK_ERROR) begin
                total_amount <= '0;
                change_reg   <= '0;
            end
        end
    end

    //=========================================================
    // Next-state logic
    //=========================================================
    always_comb begin
        next_state = state;

        case (state)

            IDLE: begin
                if (coin_valid)
                    next_state = COIN_INSERTED;
            end

            COIN_INSERTED: begin
                // Selection is considered only when enough money
                // has already been inserted.
                if (item_select && (total_amount >= item_price))
                    next_state = ITEM_SELECTED;
            end

            ITEM_SELECTED: begin
                if (!stock_available)
                    next_state = OUT_OF_STOCK_ERROR;
                else if (total_amount >= item_price)
                    next_state = DISPENSING;
                else
                    next_state = COIN_INSERTED;
            end

            DISPENSING: begin
                if (total_amount > item_price)
                    next_state = CHANGE_RETURN;
                else
                    next_state = IDLE;
            end

            CHANGE_RETURN: begin
                next_state = IDLE;
            end

            OUT_OF_STOCK_ERROR: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    //=========================================================
    // Output logic
    //=========================================================
    always_comb begin
        dispense      = 1'b0;
        change_amount = '0;
        error         = 1'b0;

        case (state)

            DISPENSING: begin
                dispense = 1'b1;
            end

            CHANGE_RETURN: begin
                change_amount = change_reg;
            end

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
