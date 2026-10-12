module counter_param #(parameter WIDTH = 8, parameter MOD = 200) (
    input clk,
    input rst_n,
    input en,
    output [7:0] count,
    output tc
);
    reg [WIDTH-1:0] count_reg;
    wire [WIDTH-1:0] next_count;
    reg tc_reg;
    
    assign count = count_reg[7:0];
    assign tc = tc_reg;
    assign next_count = (count_reg == MOD - 1) ? {WIDTH{1'b0}} : count_reg + 1;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            count_reg <= {WIDTH{1'b0}};
            tc_reg <= 1'b0;
        end
        else if (en) begin
            count_reg <= next_count;
            tc_reg <= (count_reg == MOD - 1) ? 1'b1 : 1'b0;
        end
        else begin
            tc_reg <= 1'b0;
        end
    end
endmodule
