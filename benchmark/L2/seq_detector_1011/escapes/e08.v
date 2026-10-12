module seq_detector_1011 (
    input clk,
    input rst_n,
    input din,
    output det
);

reg [3:0] state;
reg det_reg;

// 状态机定义
// 0000 - 初始状态
// 0001 - 已接收 '1'
// 0010 - 已接收 '10'
// 0011 - 已接收 '101'
// 0100 - 已接收 '1011' (检测到目标序列)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= 4'b0000;
        det_reg <= 1'b0;
    end else begin
        case (state)
            4'b0000: begin
                if (din == 1'b1)
                    state <= 4'b0001;
                else
                    state <= 4'b0000;
            end
            4'b0001: begin
                if (din == 1'b0)
                    state <= 4'b0010;
                else
                    state <= 4'b0001;
            end
            4'b0010: begin
                if (din == 1'b1)
                    state <= 4'b0011;
                else
                    state <= 4'b0000;
            end
            4'b0011: begin
                if (din == 1'b1)
                    state <= 4'b0100;
                else
                    state <= 4'b0010;
            end
            4'b0100: begin
                if (din == 1'b1)
                    state <= 4'b0100;
                else if (din == 1'b0)
                    state <= 4'b0010;
                else
                    state <= 4'b0000;
            end
            default:
                state <= 4'b0000;
        endcase

        // 检测到目标序列后，在下一个周期输出脉冲
        if (state == 4'b0100)
            det_reg <= 1'b1;
        else
            det_reg <= 1'b0;
    end
end

assign det = det_reg;

endmodule
