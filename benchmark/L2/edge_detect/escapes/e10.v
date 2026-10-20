module edge_detect (
    input clk,
    input rst_n,
    input sig,
    input [1:0] mode,
    output pulse,
    output [7:0] cnt
);

    reg [7:0] cnt_reg;
    reg sig_d1, sig_d2;
    
    // 同步输入信号到寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sig_d1 <= 1'b0;
            sig_d2 <= 1'b0;
            cnt_reg <= 8'b0;
        end else begin
            sig_d1 <= sig;
            sig_d2 <= sig_d1;
            if (pulse) begin
                cnt_reg <= cnt_reg + 1'b1;
            end
        end
    end
    
    // 边沿检测逻辑 - 组合输出
    wire rising_edge = (sig_d2 == 1'b0) && (sig_d1 == 1'b1);
    wire falling_edge = (sig_d2 == 1'b1) && (sig_d1 == 1'b0);
    
    assign pulse = (mode == 2'b00) ? rising_edge :
                   (mode == 2'b01) ? falling_edge :
                   (mode == 2'b10) ? (rising_edge || falling_edge) : 1'b0;
    
    assign cnt = cnt_reg;

endmodule
