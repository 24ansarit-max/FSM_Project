module vending_machine #(
    parameter int WIDTH = 8
)(
    input  logic             clk,
    input  logic             reset,

    // Coin inputs
    input  logic             coin_valid,
    input  logic [WIDTH-1:0] coin_value,     // 1,2,5,10

    // Item inputs
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

    logic [WIDTH-1:0] total_coins;
    logic [WIDTH-1:0] change_reg;

    // ------------------------------------------------
    // State register and coin/amount storage
    // ------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            state       <= IDLE;
            total_coins <= '0;
            change_reg  <= '0;
        end
        else begin
            state <= next_state;

            // Accept coins
            if (coin_valid &&
                ((state == IDLE) || (state == COIN_INSERTED))) begin
                total_coins <= total_coins + coin_value;
            end

            // Calculate change after valid selection
            if ((state == ITEM_SELECTED) &&
                stock_available &&
                (total_coins >= item_price)) begin
                change_reg <= total_coins - item_price;
            end

            // Clear transaction after change is returned
            if (state == CHANGE_RETURN) begin
                total_coins <= '0;
                change_reg  <= '0;
            end

            // Refund coins when item is out of stock
            if (state == OUT_OF_STOCK_ERROR) begin
                total_coins <= '0;
                change_reg  <= total_coins;
            end
        end
    end

    // ------------------------------------------------
    // Next-state logic
    // ------------------------------------------------
    always_comb begin
        next_state = state;

        case (state)

            // ----------------------------------------
            // IDLE
            // ----------------------------------------
            IDLE: begin
                if (coin_valid)
                    next_state = COIN_INSERTED;
            end

            // ----------------------------------------
            // COIN INSERTED
            // ----------------------------------------
            COIN_INSERTED: begin
                if (item_select)
                    next_state = ITEM_SELECTED;
                else if (coin_valid)
                    next_state = COIN_INSERTED;
            end

            // ----------------------------------------
            // ITEM SELECTED
            // ----------------------------------------
            ITEM_SELECTED: begin
                if (!stock_available)
                    next_state = OUT_OF_STOCK_ERROR;

                else if (total_coins >= item_price)
                    next_state = DISPENSING;

                else
                    next_state = COIN_INSERTED;
            end

            // ----------------------------------------
            // DISPENSING
            // ----------------------------------------
            DISPENSING: begin
                if (total_coins > item_price)
                    next_state = CHANGE_RETURN;
                else
                    next_state = IDLE;
            end

            // ----------------------------------------
            // CHANGE RETURN
            // ----------------------------------------
            CHANGE_RETURN: begin
                next_state = IDLE;
            end

            // ----------------------------------------
            // OUT OF STOCK / ERROR
            // ----------------------------------------
            OUT_OF_STOCK_ERROR: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    // ------------------------------------------------
    // Output logic
    // ------------------------------------------------
    always_comb begin
        dispense      = 1'b0;
        change_amount  = '0;
        error          = 1'b0;

        case (state)

            DISPENSING: begin
                dispense = 1'b1;
            end

            CHANGE_RETURN: begin
                change_amount = change_reg;
            end

            OUT_OF_STOCK_ERROR: begin
                error = 1'b1;
                change_amount = total_coins;
            end

            default: begin
                dispense      = 1'b0;
                change_amount = '0;
                error         = 1'b0;
            end

        endcase
    end

endmodule
