module pwm_gen (
    input clk,
    input rst_n,
    input [7:0] duty,
    output pwm
);

    reg [7:0] counter;
    reg [7:0] duty_latch;
    reg [7:0] duty_latch_d1;
    reg [7:0] counter_d1;
    reg pwm_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 8'd0;
            duty_latch <= 8'd0;
            duty_latch_d1 <= 8'd0;
            counter_d1 <= 8'd0;
            pwm_r <= 1'b0;
        end else begin
            if (counter == 8'd255)
                counter <= 8'd0;
            else
                counter <= counter + 8'd1;

            if (counter == 8'd255)
                duty_latch <= duty;

            duty_latch_d1 <= duty_latch;
            counter_d1 <= counter;
            pwm_r <= (counter_d1 < duty_latch_d1);
        end
    end

    assign pwm = pwm_r;

endmodule
