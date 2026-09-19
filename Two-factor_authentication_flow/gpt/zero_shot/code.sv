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
    output reg [3:0] fail_count,
    output reg [2:0] state_debug
);

    // =========================================================
    // STATE DEFINITIONS
    // =========================================================
    localparam PASSWORD_ENTRY   = 3'b000;
    localparam PASSWORD_VERIFIED= 3'b001;
    localparam OTP_SENT         = 3'b010;
    localparam OTP_VERIFY       = 3'b011;
    localparam ACCESS_GRANTED   = 3'b100;
    localparam LOCKED           = 3'b101;

    reg [2:0] state;
    reg [2:0] next_state;

    // Separate retry counters for each authentication stage.
    reg [1:0] password_fail_count;
    reg [1:0] otp_fail_count;

    // =========================================================
    // STATE REGISTER AND SECURITY COUNTERS
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            state              <= PASSWORD_ENTRY;
            password_fail_count <= 2'd0;
            otp_fail_count      <= 2'd0;
        end
        else begin
            state <= next_state;

            case (state)

                PASSWORD_ENTRY: begin
                    if (password_submit) begin

                        if (password_valid) begin
                            // Correct password starts a new OTP stage.
                            password_fail_count <= 2'd0;
                        end
                        else if (password_fail_count < 2'd3) begin
                            // SECURITY:
                            // Every incorrect password attempt increments
                            // the password retry counter.
                            password_fail_count <= password_fail_count + 1'b1;
                        end
                    end
                end

                OTP_SENT: begin
                    if (timeout_tick && !otp_submit) begin
                        // SECURITY:
                        // OTP timeout counts exactly like a failed OTP
                        // attempt. Three timeout failures cause LOCKED.
                        if (otp_fail_count < 2'd3)
                            otp_fail_count <= otp_fail_count + 1'b1;
                    end
                end

                OTP_VERIFY: begin
                    if (otp_submit) begin

                        if (otp_valid) begin
                            // Successful OTP clears OTP retry history.
                            otp_fail_count <= 2'd0;
                        end
                        else if (otp_fail_count < 2'd3) begin
                            // SECURITY:
                            // Every incorrect OTP attempt increments the
                            // independent OTP retry counter.
                            otp_fail_count <= otp_fail_count + 1'b1;
                        end
                    end
                end

                ACCESS_GRANTED: begin
                    // Successful authentication.
                    // Counters remain cleared.
                end

                LOCKED: begin
                    // SECURITY:
                    // LOCKED state never modifies its counters.
                    // Only reset can leave this state.
                    password_fail_count <= password_fail_count;
                    otp_fail_count      <= otp_fail_count;
                end

                default: begin
                    password_fail_count <= 2'd0;
                    otp_fail_count      <= 2'd0;
                end

            endcase
        end
    end

    // =========================================================
    // NEXT-STATE LOGIC
    // =========================================================
    always @(*) begin
        next_state = state;

        case (state)

            PASSWORD_ENTRY: begin
                if (password_submit) begin
                    if (password_valid) begin
                        next_state = PASSWORD_VERIFIED;
                    end
                    else if (password_fail_count >= 2'd2) begin
                        // SECURITY:
                        // Third consecutive failed password attempt
                        // immediately locks the controller.
                        next_state = LOCKED;
                    end
                    else begin
                        next_state = PASSWORD_ENTRY;
                    end
                end
            end

            PASSWORD_VERIFIED: begin
                next_state = OTP_SENT;
            end

            OTP_SENT: begin
                if (otp_submit) begin
                    next_state = OTP_VERIFY;
                end
                else if (timeout_tick) begin
                    if (otp_fail_count >= 2'd2) begin
                        // SECURITY:
                        // Third OTP timeout causes permanent lockout.
                        next_state = LOCKED;
                    end
                    else begin
                        // Retry OTP delivery after a timeout.
                        next_state = OTP_SENT;
                    end
                end
            end

            OTP_VERIFY: begin
                if (otp_submit) begin
                    if (otp_valid) begin
                        next_state = ACCESS_GRANTED;
                    end
                    else if (otp_fail_count >= 2'd2) begin
                        // SECURITY:
                        // Third consecutive failed OTP attempt causes
                        // permanent lockout.
                        next_state = LOCKED;
                    end
                    else begin
                        next_state = OTP_SENT;
                    end
                end
            end

            ACCESS_GRANTED: begin
                // Authentication is complete.
                next_state = ACCESS_GRANTED;
            end

            LOCKED: begin
                // SECURITY:
                // LOCKED has NO transition back to any authentication
                // state. Only synchronous reset can clear the lockout.
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
        access_granted = 1'b0;
        locked_out     = 1'b0;
        request_otp    = 1'b0;

        // Debug output exposes the current FSM state.
        state_debug = state;

        // Report the retry counter for the currently active stage.
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

                // OTP sending request remains asserted while waiting
                // for the OTP submission or timeout.
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
                // Access is permanently denied until reset.
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
