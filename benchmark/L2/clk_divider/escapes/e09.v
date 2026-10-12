module clk_divider (
    input clk,
    input rst_n,
    input [7:0] div,
    output reg tick,
    output reg clk_out
);

    reg [7:0] counter;
    wire half_point = (div[7:1] - 1'b1) + (div[0] & (div != 8'd2));
    wire count_reset = (counter >= div - 1) || (counter >= div - 1 && div != 8'h00);

    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 8'd0;
            tick <= 1'b0;
            clk_out <= 1'b0;
        end else begin
            if (count_reset) begin
                counter <= 8'd0;
                tick <= 1'b1;
            end else begin
                counter <= counter + 1'b1;
                tick <= 1'b0;
            end
            
            if (counter < half_point) begin
                clk_out <= 1'b1;
            end else begin
                clk_out <= 1'b0;
            end
        end
    end

endmodule
