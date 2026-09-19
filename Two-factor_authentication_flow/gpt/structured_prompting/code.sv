module two_factor_auth_controller #(
    parameter MAX_PWD_RETRIES   = 3,
    parameter MAX_OTP_RETRIES   = 3,
    parameter OTP_TIMEOUT_LIMIT = 10
)(
    input clk,
    input reset,

    input password_submit,
    input password_valid,

    input otp_submit,
    input otp_valid,

    input timeout_tick,

    output reg       access_granted,
    output reg       locked_out,
    output reg       request_otp,
    output reg [1:0] pwd_fail_count,
    output reg [1:0] otp_fail_count
);

    localparam PASSWORD_ENTRY    = 3'b000;
    localparam PASSWORD_VERIFIED = 3'b001;
    localparam OTP_SENT          = 3'b010;
    localparam OTP_VERIFY        = 3'b011;
    localparam ACCESS_GRANTED    = 3'b100;
    localparam LOCKED            = 3'b101;

    reg [2:0] state;
    reg [2:0] next_state;

    reg [3:0] otp_timeout_counter;
    reg [3:0] next_otp_timeout_counter;

    /* State register and counters */
    always @(posedge clk) begin
        if (reset) begin
            state               <= PASSWORD_ENTRY;
            pwd_fail_count      <= 2'd0;
            otp_fail_count      <= 2'd0;
            otp_timeout_counter <= 4'd0;
        end
        else begin
            state               <= next_state;
            otp_timeout_counter <= next_otp_timeout_counter;

            case (state)

                PASSWORD_ENTRY: begin
                    if (password_submit) begin
                        if (password_valid) begin
                            pwd_fail_count <= 2'd0;
                        end
                        else begin
                            // SECURITY:
                            // Count each wrong password attempt.
                            if (pwd_fail_count < MAX_PWD_RETRIES)
                                pwd_fail_count <= pwd_fail_count + 1'b1;
                        end
                    end
                end

                PASSWORD_VERIFIED: begin
                    // Password accepted; OTP flow starts next.
                    otp_fail_count <= 2'd0;
                end

                OTP_SENT: begin
                    // New OTP starts with a fresh timeout counter.
                    otp_timeout_counter <= 4'd0;
                end

                OTP_VERIFY: begin
                    if (otp_submit) begin
                        if (otp_valid) begin
                            otp_fail_count <= 2'd0;
                        end
                        else begin
                            // SECURITY:
                            // Count each wrong OTP submission.
                            if (otp_fail_count < MAX_OTP_RETRIES)
                                otp_fail_count <= otp_fail_count + 1'b1;
                        end
                    end
                    else if (timeout_tick) begin
                        // SECURITY:
                        // Timeout is handled as an OTP failure when
                        // the configured timeout limit is reached.
                        if ((otp_timeout_counter + 1'b1) >=
                            OTP_TIMEOUT_LIMIT) begin
                            otp_timeout_counter <= 4'd0;

                            if (otp_fail_count < MAX_OTP_RETRIES)
                                otp_fail_count <= otp_fail_count + 1'b1;
                        end
                    end
                end

                ACCESS_GRANTED: begin
                    // Access remains granted until reset.
                    state <= ACCESS_GRANTED;
                end

                LOCKED: begin
                    // SECURITY:
                    // LOCKED has no normal exit.
                    // Only synchronous reset can leave this state.
                    state <= LOCKED;
                end

                default: begin
                    state               <= PASSWORD_ENTRY;
                    pwd_fail_count      <= 2'd0;
                    otp_fail_count      <= 2'd0;
                    otp_timeout_counter <= 4'd0;
                end

            endcase
        end
    end

    /* Next-state combinational logic */
    always @(*) begin
        next_state = state;
        next_otp_timeout_counter = otp_timeout_counter;

        case (state)

            PASSWORD_ENTRY: begin
                if (password_submit) begin
                    if (password_valid) begin
                        next_state = PASSWORD_VERIFIED;
                    end
                    else if ((pwd_fail_count + 1'b1) >= MAX_PWD_RETRIES) begin
                        // SECURITY:
                        // Third wrong password causes permanent lockout.
                        next_state = LOCKED;
                    end
                    else begin
                        next_state = PASSWORD_ENTRY;
                    end
                end
            end

            PASSWORD_VERIFIED: begin
                next_state = OTP_SENT;
                next_otp_timeout_counter = 4'd0;
            end

            OTP_SENT: begin
                next_state = OTP_VERIFY;
                next_otp_timeout_counter = 4'd0;
            end

            OTP_VERIFY: begin

                if (otp_submit) begin
                    if (otp_valid) begin
                        next_state = ACCESS_GRANTED;
                        next_otp_timeout_counter = 4'd0;
                    end
                    else if ((otp_fail_count + 1'b1) >= MAX_OTP_RETRIES) begin
                        // SECURITY:
                        // Third wrong OTP causes permanent lockout.
                        next_state = LOCKED;
                        next_otp_timeout_counter = 4'd0;
                    end
                    else begin
                        next_state = OTP_SENT;
                        next_otp_timeout_counter = 4'd0;
                    end
                end

                else if (timeout_tick) begin
                    // SECURITY:
                    // Count timeout ticks. Reaching the timeout limit
                    // counts as one failed OTP attempt.
                    if ((otp_timeout_counter + 1'b1) >=
                        OTP_TIMEOUT_LIMIT) begin

                        next_otp_timeout_counter = 4'd0;

                        if ((otp_fail_count + 1'b1) >= MAX_OTP_RETRIES) begin
                            // SECURITY:
                            // Third timeout causes permanent lockout.
                            next_state = LOCKED;
                        end
                        else begin
                            next_state = OTP_SENT;
                        end
                    end
                    else begin
                        next_otp_timeout_counter =
                            otp_timeout_counter + 1'b1;
                    end
                end
            end

            ACCESS_GRANTED: begin
                next_state = ACCESS_GRANTED;
            end

            LOCKED: begin
                // SECURITY:
                // Highest-priority lockout enforcement.
                // No input can exit LOCKED; reset is handled separately.
                next_state = LOCKED;
            end

            default: begin
                next_state = PASSWORD_ENTRY;
            end

        endcase
    end

    /* Output logic */
    always @(*) begin
        access_granted = 1'b0;
        locked_out     = 1'b0;

        // One-cycle pulse whenever FSM is in OTP_SENT.
        request_otp = (state == OTP_SENT);

        case (state)

            PASSWORD_ENTRY: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;
            end

            PASSWORD_VERIFIED: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;
            end

            OTP_SENT: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;
            end

            OTP_VERIFY: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;
            end

            ACCESS_GRANTED: begin
                access_granted = 1'b1;
                locked_out     = 1'b0;
            end

            LOCKED: begin
                // SECURITY:
                // Access is always denied in LOCKED state.
                access_granted = 1'b0;
                locked_out     = 1'b1;
            end

            default: begin
                access_granted = 1'b0;
                locked_out     = 1'b0;
            end

        endcase
    end

endmodule
