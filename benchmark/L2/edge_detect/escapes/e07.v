module edge_detect (
    input clk,
    input rst_n,
    input sig,
    input [1:0] mode,
    output reg pulse,
    output reg [7:0] cnt
);

reg sig_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sig_d <= 1'b0;
        pulse <= 1'b0;
        cnt <= 8'b0;
    end else begin
        sig_d <= sig;
        pulse <= 1'b0; // 默认为0
        
        case (mode)
            2'b00: begin // 上升沿检测
                if (sig & ~sig_d) begin
                    pulse <= 1'b1;
                    cnt <= cnt + 1;
                end
            end
            2'b01: begin // 下降沿检测
                if (~sig & sig_d) begin
                    pulse <= 1'b1;
                    cnt <= cnt + 1;
                end
            end
            2'b10: begin // 双边沿检测
                if ((sig & ~sig_d) | (~sig & sig_d)) begin
                    pulse <= 1'b1;
                    cnt <= cnt + 1;
                end
            end
            default: begin
                pulse <= 1'b0;
            end
        endcase
    end
end

endmodule
