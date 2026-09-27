`timescale 1ns/1ps

module two_factor_auth #(
    parameter int unsigned MAX_RETRIES = 3
)(
    input  logic clk,
    input  logic reset,          // Active-high synchronous reset

    input  logic password_valid,
    input  logic otp_valid,
    input  logic otp_timeout,
    input  logic submit,

    output logic request_otp,
    output logic access_granted,
    output logic locked_out,

    // Number of failed attempts for the current stage
    output logic [2:0] retry_count
);

    //============================================================
    // STATE DEFINITIONS
    //============================================================

    typedef enum logic [2:0] {
        PASSWORD_ENTRY    = 3'b000,
        PASSWORD_VERIFIED = 3'b001,
        OTP_SENT          = 3'b010,
        OTP_VERIFY        = 3'b011,
        ACCESS_GRANTED    = 3'b100,
        LOCKED            = 3'b101
    } state_t;

    state_t current_state;
    state_t next_state;

    //============================================================
    // RETRY COUNTERS
    //============================================================

    localparam int RETRY_WIDTH =
        (MAX_RETRIES <= 1) ? 1 : $clog2(MAX_RETRIES + 1);

    logic [RETRY_WIDTH-1:0] password_retry;
    logic [RETRY_WIDTH-1:0] otp_retry;

    //============================================================
    // 1. STATE AND COUNTER REGISTER
    //============================================================

    always_ff @(posedge clk) begin

        if (reset) begin
            current_state  <= PASSWORD_ENTRY;
            password_retry <= '0;
            otp_retry      <= '0;
        end

        else begin
            current_state <= next_state;

            //----------------------------------------------------
            // PASSWORD FAILURE
            //----------------------------------------------------
            if ((current_state == PASSWORD_ENTRY) &&
                submit &&
                !password_valid) begin

                if (password_retry < MAX_RETRIES)
                    password_retry <= password_retry + 1'b1;
            end

            //----------------------------------------------------
            // OTP FAILURE OR TIMEOUT
            //----------------------------------------------------
            if ((current_state == OTP_VERIFY) &&
                ((submit && !otp_valid) || otp_timeout)) begin

                if (otp_retry < MAX_RETRIES)
                    otp_retry <= otp_retry + 1'b1;
            end

            //----------------------------------------------------
            // RESET OTP RETRY COUNT WHEN STARTING OTP PROCESS
            //----------------------------------------------------
            if ((current_state == PASSWORD_VERIFIED) &&
                submit) begin

                otp_retry <= '0;
            end
        end
    end

    //============================================================
    // 2. NEXT STATE LOGIC
    //============================================================

    always_comb begin

        // Default: remain in current state
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

                    else if (password_retry >= MAX_RETRIES - 1) begin
                        // Maximum attempts reached
                        next_state = LOCKED;
                    end

                    else begin
                        // Try password again
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

                // OTP send trigger is asserted in this state.
                // Then move to OTP verification.
                next_state = OTP_VERIFY;

            end

            //----------------------------------------------------
            // OTP VERIFY
            //----------------------------------------------------
            OTP_VERIFY: begin

                //------------------------------------------------
                // Correct OTP
                //------------------------------------------------
                if (otp_valid) begin
                    next_state = ACCESS_GRANTED;
                end

                //------------------------------------------------
                // OTP TIMEOUT
                //------------------------------------------------
                else if (otp_timeout) begin

                    if (otp_retry >= MAX_RETRIES - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;

                end

                //------------------------------------------------
                // Wrong OTP
                //------------------------------------------------
                else if (submit && !otp_valid) begin

                    if (otp_retry >= MAX_RETRIES - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_VERIFY;

                end
            end

            //----------------------------------------------------
            // ACCESS GRANTED
            //----------------------------------------------------
            ACCESS_GRANTED: begin

                // Remain authenticated until reset
                next_state = ACCESS_GRANTED;

            end

            //----------------------------------------------------
            // LOCKED
            //----------------------------------------------------
            LOCKED: begin

                // Remain locked until reset
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

        // Safe default outputs
        request_otp    = 1'b0;
        access_granted = 1'b0;
        locked_out     = 1'b0;
        retry_count    = 3'd0;

        case (current_state)

            //----------------------------------------------------
            // OTP SENT
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
                // Outputs remain LOW
            end

        endcase

        //--------------------------------------------------------
        // RETRY DISPLAY
        //--------------------------------------------------------

        if (current_state == PASSWORD_ENTRY)
            retry_count = password_retry;

        else if (current_state == OTP_VERIFY)
            retry_count = otp_retry;

        else
            retry_count = 3'd0;

    end

endmodule
