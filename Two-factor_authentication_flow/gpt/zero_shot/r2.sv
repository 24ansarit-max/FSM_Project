`timescale 1ns/1ps

module two_factor_auth #(
    parameter int unsigned MAX_PASSWORD_RETRIES = 3,
    parameter int unsigned MAX_OTP_RETRIES      = 3
)(
    input  logic clk,
    input  logic reset,

    // Authentication inputs
    input  logic password_valid,
    input  logic otp_valid,
    input  logic otp_timeout,
    input  logic submit,

    // Outputs
    output logic request_otp,
    output logic access_granted,
    output logic locked_out,

    // Retry count/display
    output logic [2:0] retry_count
);

    //============================================================
    // STATE DECLARATION
    //============================================================

    typedef enum logic [2:0] {
        PASSWORD_ENTRY   = 3'b000,
        PASSWORD_VERIFIED= 3'b001,
        OTP_SENT         = 3'b010,
        OTP_VERIFY       = 3'b011,
        ACCESS_GRANTED   = 3'b100,
        LOCKED           = 3'b101
    } state_t;

    state_t current_state, next_state;

    //============================================================
    // RETRY COUNTERS
    //============================================================

    localparam int PWD_WIDTH =
        (MAX_PASSWORD_RETRIES < 2) ?
        1 : $clog2(MAX_PASSWORD_RETRIES + 1);

    localparam int OTP_WIDTH =
        (MAX_OTP_RETRIES < 2) ?
        1 : $clog2(MAX_OTP_RETRIES + 1);

    logic [PWD_WIDTH-1:0] password_retry;
    logic [OTP_WIDTH-1:0] otp_retry;

    //============================================================
    // 1. STATE REGISTER
    //============================================================

    always_ff @(posedge clk) begin
        if (reset) begin
            current_state  <= PASSWORD_ENTRY;
            password_retry <= '0;
            otp_retry      <= '0;
        end
        else begin
            current_state <= next_state;

            // Password retry counter
            if (current_state == PASSWORD_ENTRY &&
                submit &&
                !password_valid) begin

                if (password_retry < MAX_PASSWORD_RETRIES)
                    password_retry <= password_retry + 1'b1;
            end

            // OTP retry counter
            if (current_state == OTP_VERIFY &&
                ((submit && !otp_valid) || otp_timeout)) begin

                if (otp_retry < MAX_OTP_RETRIES)
                    otp_retry <= otp_retry + 1'b1;
            end

            // Start OTP retry count after password is verified
            if (current_state == PASSWORD_VERIFIED &&
                submit) begin
                otp_retry <= '0;
            end
        end
    end

    //============================================================
    // 2. NEXT-STATE LOGIC
    //============================================================

    always_comb begin

        next_state = current_state;

        case (current_state)

            //----------------------------------------------------
            // PASSWORD ENTRY
            //----------------------------------------------------
            PASSWORD_ENTRY: begin

                if (submit) begin

                    if (password_valid) begin
                        next_state = PASSWORD_VERIFIED;
                    end

                    else if (password_retry >=
                             MAX_PASSWORD_RETRIES - 1) begin
                        // Third failure -> LOCKED
                        next_state = LOCKED;
                    end

                    else begin
                        // Allow another password attempt
                        next_state = PASSWORD_ENTRY;
                    end
                end
            end

            //----------------------------------------------------
            // PASSWORD VERIFIED
            //----------------------------------------------------
            PASSWORD_VERIFIED: begin

                if (submit)
                    next_state = OTP_SENT;
            end

            //----------------------------------------------------
            // OTP SENT
            //----------------------------------------------------
            OTP_SENT: begin

                // OTP sending trigger is generated in this state.
                // Next cycle, begin OTP verification.
                next_state = OTP_VERIFY;
            end

            //----------------------------------------------------
            // OTP VERIFY
            //----------------------------------------------------
            OTP_VERIFY: begin

                // Correct OTP
                if (otp_valid) begin
                    next_state = ACCESS_GRANTED;
                end

                // OTP timed out
                else if (otp_timeout) begin

                    if (otp_retry >= MAX_OTP_RETRIES - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;
                end

                // Wrong OTP submitted
                else if (submit && !otp_valid) begin

                    if (otp_retry >= MAX_OTP_RETRIES - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_VERIFY;
                end
            end

            //----------------------------------------------------
            // ACCESS GRANTED
            //----------------------------------------------------
            ACCESS_GRANTED: begin
                // Stay authenticated until reset
                next_state = ACCESS_GRANTED;
            end

            //----------------------------------------------------
            // LOCKED
            //----------------------------------------------------
            LOCKED: begin
                // Stay locked until reset
                next_state = LOCKED;
            end

            //----------------------------------------------------
            // DEFAULT
            //----------------------------------------------------
            default: begin
                next_state = PASSWORD_ENTRY;
            end

        endcase
    end

    //============================================================
    // 3. OUTPUT LOGIC
    //============================================================

    always_comb begin

        // Safe defaults
        request_otp    = 1'b0;
        access_granted = 1'b0;
        locked_out     = 1'b0;
        retry_count    = 3'd0;

        case (current_state)

            //----------------------------------------------------
            // OTP SEND
            //----------------------------------------------------
            OTP_SENT: begin
                request_otp = 1'b1;
            end

            //----------------------------------------------------
            // ACCESS GRANTED
            //----------------------------------------------------
            ACCESS_GRANTED: begin
                access_granted = 1'b1;
            end

            //----------------------------------------------------
            // LOCKED
            //----------------------------------------------------
            LOCKED: begin
                locked_out = 1'b1;
            end

            default: begin
                // Safe outputs remain LOW
            end

        endcase

        // Display current retry count
        if (current_state == PASSWORD_ENTRY)
            retry_count = password_retry;

        else if (current_state == OTP_VERIFY)
            retry_count = otp_retry;

        else
            retry_count = 3'd0;
    end

endmodule
