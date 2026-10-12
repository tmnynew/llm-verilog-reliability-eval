module counter_param #(parameter WIDTH = 8, parameter MOD = 200) (
    input clk,
    input rst_n,
    input en,
    output [7:0] count,
    output tc
);
    reg [WIDTH-1:0] count_reg;
    
    assign count = count_reg[7:0];
    assign tc = (count_reg == MOD - 1) ? 1'b1 : 1'b0;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            count_reg <= {WIDTH{1'b0}};
        end else if (en) begin
            if (count_reg == MOD - 1) begin
                count_reg <= {WIDTH{1'b0}};
            end else begin
                count_reg <= count_reg + 1'b1;
            end
        end
    end
endmodule
