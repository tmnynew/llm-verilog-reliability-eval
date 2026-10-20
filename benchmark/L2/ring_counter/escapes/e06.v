module ring_counter (
    input clk,
    input rst_n,
    input en,
    input dir,
    output [3:0] q,
    output wrap
);
    reg [3:0] q_reg;
    reg [3:0] q_prev;
    
    assign q = q_reg;
    assign wrap = (q_reg == 4'b0001) & (q_prev != 4'b0001);
    
    wire [3:0] next_q;
    assign next_q = en ? (dir ? {q_reg[0], q_reg[3:1]} : {q_reg[2:0], q_reg[3]}) : q_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_reg <= 4'b0001;
            q_prev <= 4'b0000; // 确保复位后初始状态不产生wrap
        end else begin
            q_prev <= q_reg;
            q_reg <= next_q;
        end
    end
endmodule
