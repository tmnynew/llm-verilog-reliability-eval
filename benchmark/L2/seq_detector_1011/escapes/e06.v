module seq_detector_1011 (
    input clk,
    input rst_n,
    input din,
    output det
);

    // 状态定义
    parameter S0 = 2'b00;  // 初始状态或匹配0
    parameter S1 = 2'b01;  // 匹配1
    parameter S2 = 2'b10;  // 匹配10
    parameter S3 = 2'b11;  // 匹配101
    
    reg [1:0] current_state, next_state;
    
    // 状态转移逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= S0;
        else
            current_state <= next_state;
    end
    
    // 下一状态逻辑
    always @(*) begin
        case (current_state)
            S0: begin
                if (din == 1'b1)
                    next_state = S1;
                else
                    next_state = S0;
            end
            S1: begin
                if (din == 1'b0)
                    next_state = S2;
                else
                    next_state = S1;
            end
            S2: begin
                if (din == 1'b1)
                    next_state = S3;
                else
                    next_state = S0;
            end
            S3: begin
                if (din == 1'b1)
                    next_state = S1;  // 允许重叠，检测到'1'回到S1
                else
                    next_state = S2;  // 检测到'0'回到S2
            end
            default: next_state = S0;
        endcase
    end
    
    // 输出逻辑 - 当前状态为S3且输入为1时输出脉冲
    assign det = (current_state == S3 && din == 1'b1) ? 1'b1 : 1'b0;

endmodule
