`timescale 1ns/1ps

module two_factor_auth #(
    parameter int unsigned MAX_RETRIES = 3
)(
    input  logic clk,
    input  logic reset,

    // Authentication inputs
    input  logic password_valid,
    input  logic otp_valid,
    input  logic otp_timeout,
    input  logic submit,

    // Controller outputs
    output logic request_otp,
    output logic access_granted,
    output logic locked_out,

    // Retry counter/display
    output logic [RETRY_WIDTH-1:0] retry_count
);

    //============================================================
    // RETRY COUNTER WIDTH
    //============================================================

    localparam int RETRY_WIDTH =
        (MAX_RETRIES <= 1) ? 1 : $clog2(MAX_RETRIES + 1);

    //============================================================
    // FSM STATES
    //============================================================

    typedef enum logic [2:0] {
        PASSWORD_ENTRY    = 3'b000,
        PASSWORD_VERIFIED = 3'b001,
        OTP_SENT          = 3'b010,
        OTP_VERIFY        = 3'b011,
        ACCESS_GRANTED    = 3'b100,
        LOCKED            = 3'b101
    } state_t;

    state_t state;
    state_t next_state;

    //============================================================
    // SEPARATE FAILURE COUNTERS
    //============================================================

    logic [RETRY_WIDTH-1:0] password_failures;
    logic [RETRY_WIDTH-1:0] otp_failures;

    //============================================================
    // 1. STATE AND COUNTER REGISTERS
    //============================================================

    always_ff @(posedge clk) begin

        if (reset) begin

            state             <= PASSWORD_ENTRY;
            password_failures <= '0;
            otp_failures      <= '0;

        end
        else begin

            state <= next_state;

            //----------------------------------------------------
            // PASSWORD FAILURE
            //----------------------------------------------------

            if ((state == PASSWORD_ENTRY) &&
                submit &&
                !password_valid) begin

                if (password_failures < MAX_RETRIES)
                    password_failures <= password_failures + 1'b1;
            end

            //----------------------------------------------------
            // START OTP STAGE
            //----------------------------------------------------

            if ((state == PASSWORD_VERIFIED) && submit) begin
                otp_failures <= '0;
            end

            //----------------------------------------------------
            // OTP FAILURE OR TIMEOUT
            //----------------------------------------------------

            if ((state == OTP_VERIFY) &&
                (otp_timeout || (submit && !otp_valid))) begin

                if (otp_failures < MAX_RETRIES)
                    otp_failures <= otp_failures + 1'b1;
            end

        end
    end

    //============================================================
    // 2. NEXT-STATE LOGIC
    //============================================================

    always_comb begin

        // Default: remain in current state
        next_state = state;

        case (state)

            //----------------------------------------------------
            // PASSWORD ENTRY
            //----------------------------------------------------

            PASSWORD_ENTRY: begin

                if (submit) begin

                    if (password_valid) begin

                        next_state = PASSWORD_VERIFIED;

                    end
                    else if (password_failures >=
                             MAX_RETRIES - 1) begin

                        next_state = LOCKED;

                    end
                    else begin

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

                // request_otp is asserted for this state.
                next_state = OTP_VERIFY;

            end

            //----------------------------------------------------
            // OTP VERIFY
            //----------------------------------------------------

            OTP_VERIFY: begin

                // Correct OTP takes priority
                if (otp_valid) begin

                    next_state = ACCESS_GRANTED;

                end
                else if (otp_timeout) begin

                    // Timeout consumes one OTP attempt
                    if (otp_failures >= MAX_RETRIES - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;

                end
                else if (submit && !otp_valid) begin

                    // Wrong OTP consumes one OTP attempt
                    if (otp_failures >= MAX_RETRIES - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;

                end

            end

            //----------------------------------------------------
            // ACCESS GRANTED
            //----------------------------------------------------

            ACCESS_GRANTED: begin

                // Remain granted until reset
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
    // 3. MOORE OUTPUT LOGIC
    //============================================================

    always_comb begin

        // Safe defaults
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
                // Outputs remain LOW
            end

        endcase
    end

    //============================================================
    // RETRY COUNT / DISPLAY
    //============================================================

    always_comb begin

        if (state == PASSWORD_ENTRY)
            retry_count = password_failures;

        else if (state == OTP_VERIFY)
            retry_count = otp_failures;

        else
            retry_count = '0;

    end

endmodule
