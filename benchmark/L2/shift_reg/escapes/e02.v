module shift_reg (
    input clk,
    input rst_n,
    input [1:0] mode,
    input [7:0] d_in,
    input s_in,
    output [7:0] q,
    output s_out
);

reg [7:0] q_reg;

assign q = q_reg;
assign s_out = (mode == 2'b01) ? q_reg[7] : (mode == 2'b10) ? q_reg[0] : 1'bx;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        q_reg <= 8'b0;
    end else begin
        case (mode)
            2'b00: q_reg <= q_reg;           // 保持
            2'b01: q_reg <= {q_reg[6:0], s_in}; // 左移
            2'b10: q_reg <= {s_in, q_reg[7:1]}; // 右移
            2'b11: q_reg <= d_in;           // 并行装载
            default: q_reg <= q_reg;
        endcase
    end
end

endmodule
