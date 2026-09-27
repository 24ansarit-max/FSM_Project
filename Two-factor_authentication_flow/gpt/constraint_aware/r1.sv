`timescale 1ns/1ps

module two_factor_auth #(
    parameter int unsigned MAX_ATTEMPTS        = 3,
    parameter int unsigned OTP_TIMEOUT_WIDTH   = 16,
    parameter int unsigned OTP_TIMEOUT_CYCLES  = 50_000
)(
    input  logic clk,
    input  logic reset,          // Active-high synchronous reset

    input  logic password_valid,
    input  logic otp_valid,
    input  logic submit,

    output logic request_otp,
    output logic access_granted,
    output logic locked_out,

    output logic [OTP_TIMEOUT_WIDTH-1:0] retry_count
);

    //============================================================
    // PARAMETER / WIDTH CALCULATIONS
    //============================================================

    localparam int RETRY_WIDTH =
        (MAX_ATTEMPTS <= 1) ? 1 : $clog2(MAX_ATTEMPTS + 1);

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

    //============================================================
    // STATE REGISTERS
    //============================================================

    state_t state;
    state_t next_state;

    //============================================================
    // RETRY COUNTERS
    //============================================================

    logic [RETRY_WIDTH-1:0] password_attempts;
    logic [RETRY_WIDTH-1:0] otp_attempts;

    //============================================================
    // OTP TIMEOUT COUNTER
    //============================================================

    logic [OTP_TIMEOUT_WIDTH-1:0] otp_timer;
    logic                         otp_timeout;

    localparam logic [OTP_TIMEOUT_WIDTH-1:0] OTP_TIMEOUT_LIMIT =
        OTP_TIMEOUT_CYCLES[OTP_TIMEOUT_WIDTH-1:0];

    //============================================================
    // 1. STATE REGISTER
    //============================================================

    always_ff @(posedge clk) begin

        if (reset) begin
            state <= PASSWORD_ENTRY;
        end
        else begin
            state <= next_state;
        end

    end

    //============================================================
    // 2. RETRY COUNTER LOGIC
    //============================================================

    always_ff @(posedge clk) begin

        if (reset) begin
            password_attempts <= '0;
            otp_attempts      <= '0;
        end
        else begin

            //====================================================
            // PASSWORD FAILURE
            //====================================================

            if ((state == PASSWORD_ENTRY) &&
                submit &&
                !password_valid) begin

                if (password_attempts < MAX_ATTEMPTS)
                    password_attempts <= password_attempts + 1'b1;
            end

            //====================================================
            // NEW OTP AUTHENTICATION STAGE
            //====================================================

            if ((state == PASSWORD_VERIFIED) && submit) begin
                otp_attempts <= '0;
            end

            //====================================================
            // OTP FAILURE
            //====================================================

            if ((state == OTP_VERIFY) &&
                (otp_timeout ||
                 (submit && !otp_valid))) begin

                if (otp_attempts < MAX_ATTEMPTS)
                    otp_attempts <= otp_attempts + 1'b1;
            end

        end
    end

    //============================================================
    // 3. OTP TIMEOUT COUNTER
    //============================================================

    always_ff @(posedge clk) begin

        if (reset) begin
            otp_timer <= '0;
        end
        else begin

            if (state != OTP_VERIFY) begin
                otp_timer <= '0;
            end
            else if (otp_valid) begin
                otp_timer <= '0;
            end
            else if (otp_timer < OTP_TIMEOUT_LIMIT) begin
                otp_timer <= otp_timer + 1'b1;
            end
            else begin
                otp_timer <= otp_timer;
            end

        end

    end

    //============================================================
    // OTP TIMEOUT DETECTION
    //============================================================

    always_comb begin

        if ((state == OTP_VERIFY) &&
            (otp_timer >= OTP_TIMEOUT_LIMIT))
            otp_timeout = 1'b1;
        else
            otp_timeout = 1'b0;

    end

    //============================================================
    // 4. NEXT-STATE LOGIC
    //============================================================

    always_comb begin

        next_state = state;

        case (state)

            //====================================================
            // PASSWORD ENTRY
            //====================================================

            PASSWORD_ENTRY: begin

                if (submit) begin

                    if (password_valid) begin
                        next_state = PASSWORD_VERIFIED;
                    end
                    else if (password_attempts >=
                             MAX_ATTEMPTS - 1) begin
                        next_state = LOCKED;
                    end
                    else begin
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

                // OTP request is generated in this state.
                next_state = OTP_VERIFY;

            end

            //====================================================
            // OTP VERIFY
            //====================================================

            OTP_VERIFY: begin

                // Correct OTP has highest priority.
                if (otp_valid) begin

                    next_state = ACCESS_GRANTED;

                end
                else if (otp_timeout) begin

                    if (otp_attempts >= MAX_ATTEMPTS - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;

                end
                else if (submit && !otp_valid) begin

                    if (otp_attempts >= MAX_ATTEMPTS - 1)
                        next_state = LOCKED;
                    else
                        next_state = OTP_SENT;

                end

            end

            //====================================================
            // ACCESS GRANTED
            //====================================================

            ACCESS_GRANTED: begin

                // Authentication remains granted until reset.
                next_state = ACCESS_GRANTED;

            end

            //====================================================
            // LOCKED
            //====================================================

            LOCKED: begin

                // No input can leave this state.
                // Only synchronous reset can unlock.
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
    // 5. OUTPUT LOGIC
    //============================================================

    always_comb begin

        //========================================================
        // SAFETY DEFAULTS
        //========================================================

        request_otp    = 1'b0;
        access_granted = 1'b0;
        locked_out     = 1'b0;

        //========================================================
        // OTP REQUEST
        //========================================================

        if (state == OTP_SENT)
            request_otp = 1'b1;

        //========================================================
        // HARD SAFETY OVERRIDE
        //
        // access_granted is physically forced LOW in every
        // state except ACCESS_GRANTED.
        //========================================================

        if (state == ACCESS_GRANTED)
            access_granted = 1'b1;
        else
            access_granted = 1'b0;

        //========================================================
        // LOCKOUT OUTPUT
        //
        // Only LOCKED can assert this signal.
        // LOCKED cannot transition anywhere except through reset.
        //========================================================

        if (state == LOCKED)
            locked_out = 1'b1;
        else
            locked_out = 1'b0;

    end

    //============================================================
    // 6. RETRY COUNT / DISPLAY
    //============================================================

    always_comb begin

        if (state == PASSWORD_ENTRY)
            retry_count = password_attempts;

        else if (state == OTP_VERIFY)
            retry_count = otp_attempts;

        else
            retry_count = '0;

    end

endmodule
