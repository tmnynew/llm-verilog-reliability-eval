module pwm_gen (
    input clk,
    input rst_n,
    input [7:0] duty,
    output pwm
);
    reg [7:0] counter;
    reg [7:0] current_duty;
    reg pwm_r;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 8'b0;
            current_duty <= 8'b0;
            pwm_r <= 1'b0;
        end else begin
            if (counter == 8'd0) begin
                current_duty <= duty;
            end
            counter <= counter + 1'b1;
            if (counter < current_duty) begin
                pwm_r <= 1'b1;
            end else begin
                pwm_r <= 1'b0;
            end
        end
    end
    
    assign pwm = pwm_r;
endmodule
