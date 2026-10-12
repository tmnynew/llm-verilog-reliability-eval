module pwm_gen (
    input clk,
    input rst_n,
    input [7:0] duty,
    output pwm
);

    reg [7:0] counter;
    reg pwm_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 8'b0;
            pwm_reg <= 1'b0;
        end else begin
            if (counter == 8'd255) begin
                counter <= 8'b0;
                pwm_reg <= (duty > 8'b0);
            end else begin
                counter <= counter + 1'b1;
                if (counter < duty - 1) begin
                    pwm_reg <= 1'b1;
                end else begin
                    pwm_reg <= 1'b0;
                end
            end
        end
    end
    
    assign pwm = pwm_reg;

endmodule
