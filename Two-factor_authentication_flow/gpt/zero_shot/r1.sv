`timescale 1ns/1ps

module two_factor_auth #(
    parameter int MAX_PASSWORD_RETRIES = 3,
    parameter int MAX_OTP_RETRIES      = 3
)(
    input  logic clk,
    input  logic reset,          // Active-high synchronous reset

    input  logic password_valid, // Password comparison result
    input  logic otp_valid,      // OTP comparison result
    input  logic otp_timeout,    // OTP verification timeout
    input  logic submit,        // Submit password / request OTP

    output logic request_otp,
    output logic access_granted,
    output logic locked_out,

    // Current retry count for display/debug
    output logic [$clog2(MAX_PASSWORD_RETRIES+1)-1:0] password_retry_count,
    output logic [$clog2(MAX_OTP_RETRIES+1)-1:0]      otp_retry_count
);

    //============================================================
    // WIDTH CALCULATIONS
    //============================================================
    localparam int PWD_CNT_WIDTH =
        (MAX_PASSWORD_RETRIES < 2) ? 1 :
        $clog2(MAX_PASSWORD_RETRIES + 1);

    localparam int OTP_CNT_WIDTH =
        (MAX_OTP_RETRIES < 2) ? 1 :
        $clog2(MAX_OTP_RETRIES + 1);

    //============================================================
    // STATE DECLARATION
    //============================================================
    typedef enum logic [2:0] {
        PASSWORD_ENTRY  = 3'b000,
        PASSWORD_VERIFIED = 3'b001,
        OTP_SENT        = 3'b010,
        OTP_VERIFY      = 3'b011,
        ACCESS_GRANTED  = 3'b100,
        LOCKED          = 3'b101
    } state_t;

    state_t current_state, next_state;

    //============================================================
    // RETRY COUNTERS
    //============================================================
    logic [PWD_CNT_WIDTH-1:0] password_retries;
    logic [OTP_CNT_WIDTH-1:0] otp_retries;

    //============================================================
    // STATE REGISTER + COUNTERS
    //============================================================
    always_ff @(posedge clk) begin

        if (reset) begin
            current_state   <= PASSWORD_ENTRY;
            password_retries <= '0;
            otp_retries      <= '0;
        end
        else begin
            current_state <= next_state;

            // Password retry counter
            if (current_state == PASSWORD_ENTRY &&
                submit &&
                !password_valid) begin

                if (password_retries < MAX_PASSWORD_RETRIES)
                    password_retries <= password_retries + 1'b1;
            end

            // OTP retry counter
            if (current_state == OTP_VERIFY &&
                ((submit && !otp_valid) || otp_timeout)) begin

                if (otp_retries < MAX_OTP_RETRIES)
                    otp_retries <= otp_retries + 1'b1;
            end

            // Clear OTP retries when a new authentication
            // session successfully verifies the password.
            if (current_state == PASSWORD_VERIFIED &&
                submit) begin
                otp_retries <= '0;
            end
        end
    end

    //============================================================
    // NEXT-STATE LOGIC
    //============================================================
    always_comb begin

        // Default: remain in current state
        next_state = current_state;

        case (current_state)

            //====================================================
            // PASSWORD ENTRY
            //====================================================
            PASSWORD_ENTRY: begin

                if (submit) begin

                    if (password_valid) begin
                        next_state = PASSWORD_VERIFIED;
                    end

                    else if (password_retries >=
                             MAX_PASSWORD_RETRIES-1) begin
                        // Current attempt is the final allowed
                        // failed attempt.
                        next_state = LOCKED;
                    end

                    else begin
                        // Try password again
                        next_state = PASSWORD_ENTRY;
                    end
                end
            end

            //====================================================
            // PASSWORD VERIFIED
            //====================================================
            PASSWORD_VERIFIED: begin

                if (submit)
                    next_state = OTP_SENT;
            end

            //====================================================
            // OTP SENT
            //====================================================
            OTP_SENT: begin
                // OTP is considered sent.
                // Move to OTP verification.
                next_state = OTP_VERIFY;
            end

            //====================================================
            // OTP VERIFY
            //====================================================
            OTP_VERIFY: begin

                if (otp_valid) begin
                    next_state = ACCESS_GRANTED;
                end

                else if (otp_timeout) begin

                    if (otp_retries >= MAX_OTP_RETRIES-1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;

                end

                else if (submit && !otp_valid) begin

                    if (otp_retries >= MAX_OTP_RETRIES-1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_VERIFY;
                end
            end

            //====================================================
            // ACCESS GRANTED
            //====================================================
            ACCESS_GRANTED: begin
                // Authentication successful.
                next_state = ACCESS_GRANTED;
            end

            //====================================================
            // LOCKED
            //====================================================
            LOCKED: begin
                // Permanent lock until reset.
                next_state = LOCKED;
            end

            //====================================================
            // DEFAULT
            //====================================================
            default: begin
                next_state = PASSWORD_ENTRY;
            end

        endcase
    end

    //============================================================
    // OUTPUT LOGIC
    //============================================================
    always_comb begin

        // Safe defaults
        request_otp   = 1'b0;
        access_granted = 1'b0;
        locked_out     = 1'b0;

        case (current_state)

            OTP_SENT: begin
                request_otp = 1'b1;
            end

            ACCESS_GRANTED: begin
                access_granted = 1'b1;
            end

            LOCKED: begin
                locked_out = 1'b1;
            end

            default: begin
                request_otp    = 1'b0;
                access_granted = 1'b0;
                locked_out     = 1'b0;
            end

        endcase
    end

    //============================================================
    // RETRY COUNT OUTPUTS
    //============================================================
    assign password_retry_count = password_retries;
    assign otp_retry_count      = otp_retries;

endmodule
