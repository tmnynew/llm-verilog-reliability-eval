module clk_divider (
    input clk,
    input rst_n,
    input [7:0] div,
    output tick,
    output clk_out
);
    reg [7:0] counter;
    reg tick_reg;
    reg clk_out_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 8'd0;
            tick_reg <= 1'b0;
            clk_out_reg <= 1'b1;
        end else begin
            if (counter >= div - 1) begin
                counter <= 8'd0;
                tick_reg <= 1'b1;
                clk_out_reg <= 1'b1;
            end else begin
                counter <= counter + 1;
                tick_reg <= 1'b0;
                clk_out_reg <= (counter < (div >> 1)) ? 1'b1 : 1'b0;
            end
        end
    end

    assign tick = tick_reg;
    assign clk_out = clk_out_reg;
endmodule
