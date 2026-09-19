module two_factor_auth_controller (
    input clk,
    input reset,

    input       password_valid,
    input       password_submit,
    input       otp_valid,
    input       otp_submit,
    input       timeout_tick,

    output reg       access_granted,
    output reg       locked_out,
    output reg       request_otp,
    output reg [3:0] fail_count
);

    // State definitions
    localparam PASSWORD_ENTRY    = 3'b000;
    localparam PASSWORD_VERIFIED = 3'b001;
    localparam OTP_SENT          = 3'b010;
    localparam OTP_VERIFY        = 3'b011;
    localparam ACCESS_GRANTED    = 3'b100;
    localparam LOCKED            = 3'b101;

    reg [2:0] state;

    // Separate retry counters for password and OTP stages
    reg [1:0] password_fail_count;
    reg [1:0] otp_fail_count;

    // Timeout counter
    reg [1:0] timeout_count;

    // =========================================================
    // STATE AND COUNTER REGISTER
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            state               <= PASSWORD_ENTRY;
            password_fail_count <= 2'd0;
            otp_fail_count      <= 2'd0;
            timeout_count       <= 2'd0;
        end
        else begin
            case (state)

                // -------------------------------------------------
                // PASSWORD STAGE
                // -------------------------------------------------
                PASSWORD_ENTRY: begin
                    if (password_submit) begin

                        if (password_valid) begin
                            // Correct password clears password failures.
                            password_fail_count <= 2'd0;
                            state <= PASSWORD_VERIFIED;
                        end
                        else if (password_fail_count == 2'd2) begin
                            // SECURITY:
                            // Third failed password attempt locks the user.
                            state <= LOCKED;
                        end
                        else begin
                            // Wrong password increments retry counter.
                            password_fail_count <= password_fail_count + 1'b1;
                        end
                    end
                end

                // -------------------------------------------------
                // PASSWORD VERIFIED
                // -------------------------------------------------
                PASSWORD_VERIFIED: begin
                    // Move to OTP sending stage.
                    timeout_count <= 2'd0;
                    state <= OTP_SENT;
                end

                // -------------------------------------------------
                // OTP SENT / WAITING FOR OTP
                // -------------------------------------------------
                OTP_SENT: begin

                    if (otp_submit) begin
                        state <= OTP_VERIFY;
                    end
                    else if (timeout_tick) begin

                        // SECURITY:
                        // A timeout is treated exactly like a failed
                        // OTP attempt.
                        if (otp_fail_count == 2'd2) begin
                            // Third failed/timeout OTP attempt locks.
                            state <= LOCKED;
                        end
                        else begin
                            otp_fail_count <= otp_fail_count + 1'b1;
                            timeout_count  <= 2'd0;

                            // Send another OTP for the next attempt.
                            state <= OTP_SENT;
                        end
                    end
                end

                // -------------------------------------------------
                // OTP VERIFICATION
                // -------------------------------------------------
                OTP_VERIFY: begin

                    if (otp_submit) begin

                        if (otp_valid) begin
                            // Correct OTP grants access.
                            otp_fail_count <= 2'd0;
                            state <= ACCESS_GRANTED;
                        end
                        else if (otp_fail_count == 2'd2) begin
                            // SECURITY:
                            // Third failed OTP attempt locks.
                            state <= LOCKED;
                        end
                        else begin
                            // Wrong OTP increments retry counter.
                            otp_fail_count <= otp_fail_count + 1'b1;
                            state <= OTP_SENT;
                            timeout_count <= 2'd0;
                        end
                    end
                end

                // -------------------------------------------------
                // ACCESS GRANTED
                // -------------------------------------------------
                ACCESS_GRANTED: begin
                    // Authentication completed successfully.
                    state <= ACCESS_GRANTED;
                end

                // -------------------------------------------------
                // LOCKED
                // -------------------------------------------------
                LOCKED: begin
                    // SECURITY:
                    // LOCKED has no recovery transition.
                    // Only external reset can unlock the controller.
                    state <= LOCKED;
                end

                default: begin
                    state               <= PASSWORD_ENTRY;
                    password_fail_count <= 2'd0;
                    otp_fail_count      <= 2'd0;
                    timeout_count       <= 2'd0;
                end

            endcase
        end
    end

    // =========================================================
    // OUTPUT LOGIC
    // =========================================================
    always @(*) begin

        access_granted = 1'b0;
        locked_out     = 1'b0;
        request_otp    = 1'b0;

        // Show the retry count for the currently active stage.
        if (state == PASSWORD_ENTRY)
            fail_count = {2'b00, password_fail_count};
        else
            fail_count = {2'b00, otp_fail_count};

        case (state)

            PASSWORD_ENTRY: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;
                request_otp    = 1'b0;
            end

            PASSWORD_VERIFIED: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;
                request_otp    = 1'b0;
            end

            OTP_SENT: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;

                // Request OTP while waiting for the user.
                request_otp = 1'b1;
            end

            OTP_VERIFY: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;
                request_otp    = 1'b0;
            end

            ACCESS_GRANTED: begin
                access_granted = 1'b1;
                locked_out     = 1'b0;
                request_otp    = 1'b0;
            end

            LOCKED: begin
                // SECURITY:
                // Access is always denied while LOCKED.
                access_granted = 1'b0;
                locked_out     = 1'b1;
                request_otp    = 1'b0;
            end

            default: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;
                request_otp    = 1'b0;
            end

        endcase
    end

endmodule
