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
    end else begin
        sig_d <= sig;
    end
end

wire pos_edge = (sig & ~sig_d);
wire neg_edge = (~sig & sig_d);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pulse <= 1'b0;
    end else begin
        case (mode)
            2'b00: pulse <= pos_edge;      // 上升沿检测
            2'b01: pulse <= neg_edge;      // 下降沿检测
            2'b10: pulse <= pos_edge | neg_edge; // 双边沿检测
            2'b11: pulse <= 1'b0;          // 无检测
            default: pulse <= 1'b0;
        endcase
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt <= 8'b0;
    end else if (pulse) begin
        cnt <= cnt + 1'b1;
    end
end

endmodule
