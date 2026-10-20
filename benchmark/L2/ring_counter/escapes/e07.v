module ring_counter (
    input clk,
    input rst_n,
    input en,
    input dir,
    output [3:0] q,
    output wrap
);
    reg [3:0] q_reg;
    
    assign q = q_reg;
    assign wrap = (q_reg == 4'b0001) && (q_reg != 4'b0001 || en);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_reg <= 4'b0001;
        end else if (en) begin
            if (dir) begin
                // 右移（反向）
                q_reg <= {q_reg[0], q_reg[3:1]};
            end else begin
                // 左移（正向）
                q_reg <= {q_reg[2:0], q_reg[3]};
            end
        end
    end
endmodule
