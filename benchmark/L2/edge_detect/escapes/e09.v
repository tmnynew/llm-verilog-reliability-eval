module edge_detect (
    input clk,
    input rst_n,
    input sig,
    input [1:0] mode,
    output pulse,
    output [7:0] cnt
);

    reg [1:0] sig_sync;
    reg [7:0] cnt_reg;
    wire edge_pulse;

    // 同步输入信号到时钟域
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sig_sync <= 2'b00;
            cnt_reg <= 8'b00000000;
        end else begin
            sig_sync <= {sig_sync[0], sig};
            if (edge_pulse)
                cnt_reg <= cnt_reg + 1;
        end
    end

    // 边沿检测逻辑
    wire rising_edge = (sig_sync == 2'b01);  // 上升沿：0->1
    wire falling_edge = (sig_sync == 2'b10); // 下降沿：1->0
    
    assign edge_pulse = (mode == 2'b00) ? rising_edge :
                       (mode == 2'b01) ? falling_edge :
                       (mode == 2'b10) ? (rising_edge | falling_edge) : 1'b0;

    assign pulse = edge_pulse;
    assign cnt = cnt_reg;

endmodule
