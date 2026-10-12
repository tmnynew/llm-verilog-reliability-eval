// Golden reference: 8-bit PWM with duty latched at the period boundary
module pwm_gen (
    input        clk,
    input        rst_n,
    input  [7:0] duty,
    output       pwm
);
    reg [7:0] cnt;
    reg [7:0] duty_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt    <= 8'd0;
            duty_r <= 8'd0;
        end else begin
            cnt <= cnt + 8'd1;
            if (cnt == 8'd255)
                duty_r <= duty;
        end
    end

    assign pwm = rst_n & (cnt < duty_r);
endmodule
