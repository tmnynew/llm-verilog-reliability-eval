module seq_detector_1011 (
    input clk,
    input rst_n,
    input din,
    output det
);

    // 状态定义
    parameter S0 = 2'b00, S1 = 2'b01, S2 = 2'b10, S3 = 2'b11;
    
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
                    next_state = S2;
            end
            default: next_state = S0;
        endcase
    end
    
    // 输出逻辑 - 检测到"1011"时输出脉冲
    assign det = (current_state == S3 && din == 1'b1);

endmodule
