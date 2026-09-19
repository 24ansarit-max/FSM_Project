module two_factor_auth_controller #(
    parameter OTP_TIMEOUT_TICKS = 4
)(
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

    // =========================================================
    // STATE DEFINITIONS
    // =========================================================
    localparam PASSWORD_ENTRY    = 3'b000;
    localparam PASSWORD_VERIFIED = 3'b001;
    localparam OTP_SENT          = 3'b010;
    localparam OTP_VERIFY        = 3'b011;
    localparam ACCESS_GRANTED    = 3'b100;
    localparam LOCKED            = 3'b101;

    reg [2:0] state;
    reg [2:0] next_state;

    // Separate retry counters for password and OTP.
    // Values 0,1,2 represent zero, one, or two previous failures.
    reg [1:0] password_fail_count;
    reg [1:0] otp_fail_count;

    // Counter for OTP timeout window.
    reg [3:0] timeout_count;

    // =========================================================
    // STATE REGISTER AND COUNTERS
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            state               <= PASSWORD_ENTRY;
            password_fail_count <= 2'd0;
            otp_fail_count      <= 2'd0;
            timeout_count       <= 4'd0;
        end
        else begin
            state <= next_state;

            case (state)

                // -------------------------------------------------
                // PASSWORD ENTRY
                // -------------------------------------------------
                PASSWORD_ENTRY: begin
                    if (password_submit) begin

                        if (password_valid) begin
                            // Correct password starts a fresh OTP stage.
                            password_fail_count <= 2'd0;
                        end
                        else if (password_fail_count < 2'd3) begin
                            // RETRY-LIMIT:
                            // Increment the password failure counter.
                            password_fail_count <= password_fail_count + 1'b1;
                        end
                    end
                end

                // -------------------------------------------------
                // PASSWORD VERIFIED
                // -------------------------------------------------
                PASSWORD_VERIFIED: begin
                    // New OTP request starts with a fresh timeout.
                    timeout_count <= 4'd0;
                    otp_fail_count <= 2'd0;
                end

                // -------------------------------------------------
                // OTP SENT
                // -------------------------------------------------
                OTP_SENT: begin

                    // A submitted OTP takes priority over timeout.
                    if (otp_submit) begin
                        timeout_count <= 4'd0;
                    end
                    else if (timeout_tick) begin

                        if (timeout_count < OTP_TIMEOUT_TICKS - 1) begin
                            timeout_count <= timeout_count + 1'b1;
                        end
                        else begin
                            // TIMEOUT:
                            // Expired OTP window is treated as one
                            // failed OTP attempt.
                            timeout_count <= 4'd0;

                            if (otp_fail_count < 2'd3)
                                otp_fail_count <= otp_fail_count + 1'b1;
                        end
                    end
                end

                // -------------------------------------------------
                // OTP VERIFY
                // -------------------------------------------------
                OTP_VERIFY: begin
                    if (otp_submit) begin
                        timeout_count <= 4'd0;

                        if (otp_valid) begin
                            // Correct OTP clears OTP failure history.
                            otp_fail_count <= 2'd0;
                        end
                        else if (otp_fail_count < 2'd3) begin
                            // RETRY-LIMIT:
                            // Increment OTP failure counter.
                            otp_fail_count <= otp_fail_count + 1'b1;
                        end
                    end
                end

                // -------------------------------------------------
                // ACCESS GRANTED
                // -------------------------------------------------
                ACCESS_GRANTED: begin
                    // Authentication is complete.
                    timeout_count <= 4'd0;
                end

                // -------------------------------------------------
                // LOCKED
                // -------------------------------------------------
                LOCKED: begin
                    // LOCKOUT ENFORCEMENT:
                    // Counters are held. The next-state logic below
                    // provides NO exit from LOCKED. Only reset can
                    // return the controller to PASSWORD_ENTRY.
                    state <= LOCKED;
                end

                default: begin
                    password_fail_count <= 2'd0;
                    otp_fail_count      <= 2'd0;
                    timeout_count       <= 4'd0;
                end

            endcase
        end
    end

    // =========================================================
    // NEXT-STATE COMBINATIONAL LOGIC
    // =========================================================
    always @(*) begin
        next_state = state;

        case (state)

            // -------------------------------------------------
            // PASSWORD ENTRY
            // -------------------------------------------------
            PASSWORD_ENTRY: begin
                if (password_submit) begin

                    if (password_valid) begin
                        next_state = PASSWORD_VERIFIED;
                    end
                    else if (password_fail_count == 2'd2) begin
                        // RETRY-LIMIT:
                        // This is the THIRD consecutive wrong
                        // password attempt, so lock immediately.
                        next_state = LOCKED;
                    end
                    else begin
                        next_state = PASSWORD_ENTRY;
                    end
                end
            end

            // -------------------------------------------------
            // PASSWORD VERIFIED
            // -------------------------------------------------
            PASSWORD_VERIFIED: begin
                next_state = OTP_SENT;
            end

            // -------------------------------------------------
            // OTP SENT
            // -------------------------------------------------
            OTP_SENT: begin

                if (otp_submit) begin
                    next_state = OTP_VERIFY;
                end
                else if (timeout_tick &&
                         (timeout_count >= OTP_TIMEOUT_TICKS - 1)) begin

                    // TIMEOUT CHECK:
                    // OTP was not submitted before the timeout window.
                    // Treat timeout as a failed OTP attempt.
                    if (otp_fail_count == 2'd2) begin
                        // Third OTP failure/timeout -> permanent lock.
                        next_state = LOCKED;
                    end
                    else begin
                        // Retry OTP with a new timeout window.
                        next_state = OTP_SENT;
                    end
                end
                else begin
                    next_state = OTP_SENT;
                end
            end

            // -------------------------------------------------
            // OTP VERIFY
            // -------------------------------------------------
            OTP_VERIFY: begin

                if (otp_submit) begin

                    if (otp_valid) begin
                        next_state = ACCESS_GRANTED;
                    end
                    else if (otp_fail_count == 2'd2) begin
                        // RETRY-LIMIT:
                        // This is the THIRD wrong OTP attempt.
                        next_state = LOCKED;
                    end
                    else begin
                        // Wrong OTP -> send/request another OTP.
                        next_state = OTP_SENT;
                    end
                end
                else if (timeout_tick &&
                         (timeout_count >= OTP_TIMEOUT_TICKS - 1)) begin

                    // TIMEOUT CHECK:
                    // If no OTP submission arrives within the timeout,
                    // count it as an OTP failure.
                    if (otp_fail_count == 2'd2) begin
                        next_state = LOCKED;
                    end
                    else begin
                        next_state = OTP_SENT;
                    end
                end
                else begin
                    next_state = OTP_VERIFY;
                end
            end

            // -------------------------------------------------
            // ACCESS GRANTED
            // -------------------------------------------------
            ACCESS_GRANTED: begin
                next_state = ACCESS_GRANTED;
            end

            // -------------------------------------------------
            // LOCKED
            // -------------------------------------------------
            LOCKED: begin
                // LOCKOUT ENFORCEMENT:
                // There is deliberately NO transition out of LOCKED.
                // Only the synchronous reset branch can leave LOCKED.
                next_state = LOCKED;
            end

            default: begin
                next_state = PASSWORD_ENTRY;
            end

        endcase
    end

    // =========================================================
    // OUTPUT LOGIC
    // =========================================================
    always @(*) begin

        // Safe defaults
        access_granted = 1'b0;
        locked_out     = 1'b0;
        request_otp    = 1'b0;

        // Report the active stage's failure count.
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

                // Request OTP while waiting for submission.
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
                // LOCKOUT:
                // Access can never be granted while locked.
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
