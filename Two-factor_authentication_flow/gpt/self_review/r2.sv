`timescale 1ns/1ps

module two_factor_auth #(
    parameter int unsigned MAX_ATTEMPTS       = 3,
    parameter int unsigned OTP_TIMEOUT_WIDTH  = 16,
    parameter int unsigned OTP_TIMEOUT_CYCLES = 50_000
)(
    input  logic clk,
    input  logic reset,

    input  logic password_valid,
    input  logic otp_valid,
    input  logic otp_timeout,
    input  logic submit,

    output logic request_otp,
    output logic access_granted,
    output logic locked_out,
    output logic [RETRY_WIDTH-1:0] attempt_count
);

    localparam int RETRY_WIDTH =
        (MAX_ATTEMPTS <= 1) ? 1 : $clog2(MAX_ATTEMPTS + 1);

    typedef enum logic [2:0] {
        PASSWORD_ENTRY    = 3'b000,
        PASSWORD_VERIFIED = 3'b001,
        OTP_SENT          = 3'b010,
        OTP_VERIFY        = 3'b011,
        ACCESS_GRANTED    = 3'b100,
        LOCKED            = 3'b101
    } state_t;

    state_t state, next_state;

    logic [RETRY_WIDTH-1:0] password_attempts;
    logic [RETRY_WIDTH-1:0] otp_attempts;

    logic [OTP_TIMEOUT_WIDTH-1:0] otp_timer;
    logic otp_timeout_int;

    logic submit_armed;

    localparam logic [OTP_TIMEOUT_WIDTH-1:0] TIMEOUT_LIMIT =
        OTP_TIMEOUT_CYCLES;

    //============================================================
    // STATE REGISTER
    //============================================================

    always_ff @(posedge clk) begin
        if (reset)
            state <= PASSWORD_ENTRY;
        else
            state <= next_state;
    end

    //============================================================
    // SUBMIT ARM REGISTER
    //============================================================

    always_ff @(posedge clk) begin
        if (reset)
            submit_armed <= 1'b1;
        else if (!submit)
            submit_armed <= 1'b1;
        else if (submit_armed)
            submit_armed <= 1'b0;
    end

    //============================================================
    // RETRY COUNTERS
    //============================================================

    always_ff @(posedge clk) begin
        if (reset) begin
            password_attempts <= '0;
            otp_attempts      <= '0;
        end
        else begin

            if ((state == PASSWORD_ENTRY) &&
                submit &&
                submit_armed &&
                !password_valid) begin

                if (password_attempts < MAX_ATTEMPTS)
                    password_attempts <= password_attempts + 1'b1;
            end

            if ((state == PASSWORD_VERIFIED) &&
                submit &&
                submit_armed) begin

                otp_attempts <= '0;
            end

            if ((state == OTP_VERIFY) &&
                (otp_timeout_int ||
                 (submit && submit_armed && !otp_valid))) begin

                if (otp_attempts < MAX_ATTEMPTS)
                    otp_attempts <= otp_attempts + 1'b1;
            end
        end
    end

    //============================================================
    // OTP TIMER
    //============================================================

    always_ff @(posedge clk) begin
        if (reset)
            otp_timer <= '0;
        else if (state != OTP_VERIFY)
            otp_timer <= '0;
        else if (otp_valid)
            otp_timer <= '0;
        else if (otp_timer < TIMEOUT_LIMIT)
            otp_timer <= otp_timer + 1'b1;
    end

    //============================================================
    // OTP TIMEOUT
    //============================================================

    always_comb begin
        otp_timeout_int = 1'b0;

        if ((state == OTP_VERIFY) &&
            (otp_timer >= TIMEOUT_LIMIT))
            otp_timeout_int = 1'b1;
    end

    //============================================================
    // NEXT STATE
    //============================================================

    always_comb begin

        next_state = state;

        case (state)

            PASSWORD_ENTRY: begin

                if (submit && submit_armed) begin

                    if (password_valid)
                        next_state = PASSWORD_VERIFIED;

                    else if (MAX_ATTEMPTS <= 1)
                        next_state = LOCKED;

                    else if (password_attempts >= MAX_ATTEMPTS - 1)
                        next_state = LOCKED;

                    else
                        next_state = PASSWORD_ENTRY;
                end
            end

            PASSWORD_VERIFIED: begin

                if (submit && submit_armed)
                    next_state = OTP_SENT;

            end

            OTP_SENT: begin
                next_state = OTP_VERIFY;
            end

            OTP_VERIFY: begin

                if (otp_valid)
                    next_state = ACCESS_GRANTED;

                else if (otp_timeout_int) begin

                    if (MAX_ATTEMPTS <= 1)
                        next_state = LOCKED;
                    else if (otp_attempts >= MAX_ATTEMPTS - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;

                end

                else if (submit && submit_armed && !otp_valid) begin

                    if (MAX_ATTEMPTS <= 1)
                        next_state = LOCKED;
                    else if (otp_attempts >= MAX_ATTEMPTS - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;
                end
            end

            ACCESS_GRANTED: begin
                next_state = ACCESS_GRANTED;
            end

            LOCKED: begin
                next_state = LOCKED;
            end

            default: begin
                next_state = PASSWORD_ENTRY;
            end

        endcase
    end

    //============================================================
    // OUTPUTS
    //============================================================

    always_comb begin

        request_otp    = 1'b0;
        access_granted = 1'b0;
        locked_out     = 1'b0;

        if (state == OTP_SENT)
            request_otp = 1'b1;

        if (state == ACCESS_GRANTED)
            access_granted = 1'b1;
        else
            access_granted = 1'b0;

        if (state == LOCKED)
            locked_out = 1'b1;
        else
            locked_out = 1'b0;
    end

    //============================================================
    // ATTEMPT COUNT
    //============================================================

    always_comb begin

        if (state == PASSWORD_ENTRY)
            attempt_count = password_attempts;
        else if (state == OTP_VERIFY)
            attempt_count = otp_attempts;
        else
            attempt_count = '0;

    end

endmodule
