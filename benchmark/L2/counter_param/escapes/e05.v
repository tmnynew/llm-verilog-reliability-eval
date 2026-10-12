module counter_param #(parameter WIDTH = 8, parameter MOD = 200) (
    input clk,
    input rst_n,
    input en,
    output [7:0] count,
    output tc
);
    reg [WIDTH-1:0] count_reg;
    wire [WIDTH-1:0] next_count;
    
    assign next_count = (count_reg == MOD - 1) ? {WIDTH{1'b0}} : count_reg + 1;
    assign count = count_reg[7:0];
    assign tc = (count_reg == MOD - 1);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_reg <= {WIDTH{1'b0}};
        end else if (en) begin
            count_reg <= next_count;
        end
    end
endmodule
