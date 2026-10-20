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
    wire rising_edge, falling_edge, any_edge;
    wire [7:0] cnt_next;
    
    // 同步采样输入信号
    always @(posedge clk) begin
        if (!rst_n) begin
            sig_d1 <= 1'b0;
            sig_d2 <= 1'b0;
            cnt_reg <= 8'b0;
        end else begin
            sig_d1 <= sig;
            sig_d2 <= sig_d1;
            cnt_reg <= cnt_next;
        end
    end
    
    // 边沿检测
    assign rising_edge = (sig_d2 == 1'b0) && (sig_d1 == 1'b1);
    assign falling_edge = (sig_d2 == 1'b1) && (sig_d1 == 1'b0);
    assign any_edge = rising_edge || falling_edge;
    
    // 脉冲输出
    assign pulse = (mode == 2'b00) ? rising_edge :
                   (mode == 2'b01) ? falling_edge :
                   (mode == 2'b10) ? any_edge : 1'b0;
    
    // 计数器更新
    assign cnt_next = pulse ? (cnt_reg + 1'b1) : cnt_reg;
    
    // 输出
    assign cnt = cnt_reg;

endmodule
