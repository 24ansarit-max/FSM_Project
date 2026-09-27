`timescale 1ns/1ps

module two_factor_auth #(
    parameter int unsigned MAX_RETRIES = 3
)(
    input  logic clk,
    input  logic rst,

    input  logic password_valid,
    input  logic otp_valid,
    input  logic otp_timeout,
    input  logic submit,

    output logic request_otp,
    output logic access_granted,
    output logic locked_out,

    output logic [2:0] retry_count
);

    //========================================================
    // STATES
    //========================================================
    typedef enum logic [2:0] {
        PASSWORD_ENTRY    = 3'b000,
        PASSWORD_VERIFIED = 3'b001,
        OTP_SENT          = 3'b010,
        OTP_VERIFY        = 3'b011,
        ACCESS_GRANTED    = 3'b100,
        LOCKED            = 3'b101
    } state_t;

    state_t state, next_state;

    //========================================================
    // RETRY COUNTERS
    //========================================================
    localparam int COUNT_WIDTH =
        (MAX_RETRIES <= 1) ? 1 : $clog2(MAX_RETRIES + 1);

    logic [COUNT_WIDTH-1:0] password_failures;
    logic [COUNT_WIDTH-1:0] otp_failures;

    //========================================================
    // 1. STATE AND COUNTER REGISTERS
    //========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state             <= PASSWORD_ENTRY;
            password_failures <= '0;
            otp_failures      <= '0;
        end
        else begin
            state <= next_state;

            // Count wrong password submissions
            if (state == PASSWORD_ENTRY &&
                submit &&
                !password_valid) begin

                if (password_failures < MAX_RETRIES)
                    password_failures <= password_failures + 1'b1;
            end

            // Count wrong OTP submissions or timeout
            if (state == OTP_VERIFY &&
                ((submit && !otp_valid) || otp_timeout)) begin

                if (otp_failures < MAX_RETRIES)
                    otp_failures <= otp_failures + 1'b1;
            end

            // Start OTP stage with a fresh retry count
            if (state == PASSWORD_VERIFIED && submit)
                otp_failures <= '0;
        end
    end

    //========================================================
    // 2. NEXT-STATE LOGIC
    //========================================================
    always_comb begin

        next_state = state;

        case (state)

            //================================================
            // PASSWORD ENTRY
            //================================================
            PASSWORD_ENTRY: begin

                if (submit) begin

                    if (password_valid) begin
                        next_state = PASSWORD_VERIFIED;
                    end

                    else if (password_failures >= MAX_RETRIES - 1) begin
                        next_state = LOCKED;
                    end

                    else begin
                        next_state = PASSWORD_ENTRY;
                    end

                end
            end

            //================================================
            // PASSWORD VERIFIED
            //================================================
            PASSWORD_VERIFIED: begin

                if (submit)
                    next_state = OTP_SENT;

            end

            //================================================
            // OTP SENT
            //================================================
            OTP_SENT: begin

                // request_otp is asserted in this state.
                // Move to OTP verification on next clock.
                next_state = OTP_VERIFY;

            end

            //================================================
            // OTP VERIFY
            //================================================
            OTP_VERIFY: begin

                // Correct OTP
                if (otp_valid) begin
                    next_state = ACCESS_GRANTED;
                end

                // OTP timed out
                else if (otp_timeout) begin

                    if (otp_failures >= MAX_RETRIES - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;

                end

                // Wrong OTP submitted
                else if (submit && !otp_valid) begin

                    if (otp_failures >= MAX_RETRIES - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_VERIFY;

                end
            end

            //================================================
            // ACCESS GRANTED
            //================================================
            ACCESS_GRANTED: begin
                next_state = ACCESS_GRANTED;
            end

            //================================================
            // LOCKED
            //================================================
            LOCKED: begin
                // Stay locked until reset
                next_state = LOCKED;
            end

            //================================================
            // DEFAULT
            //================================================
            default: begin
                next_state = PASSWORD_ENTRY;
            end

        endcase
    end

    //========================================================
    // 3. MOORE OUTPUT LOGIC
    //========================================================
    always_comb begin

        request_otp    = 1'b0;
        access_granted = 1'b0;
        locked_out     = 1'b0;

        case (state)

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
                // All outputs remain LOW
            end

        endcase
    end

    //========================================================
    // RETRY COUNT DISPLAY
    //========================================================
    always_comb begin

        if (state == PASSWORD_ENTRY)
            retry_count = password_failures;

        else if (state == OTP_VERIFY)
            retry_count = otp_failures;

        else
            retry_count = 3'd0;

    end

endmodule
