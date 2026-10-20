module edge_detect (
    input clk,
    input rst_n,
    input sig,
    input [1:0] mode,
    output pulse,
    output [7:0] cnt
);

    reg [7:0] cnt_reg;
    reg sig_q, sig_qq;
    
    wire rising_edge = (sig_qq == 1'b0) & (sig_q == 1'b1);
    wire falling_edge = (sig_qq == 1'b1) & (sig_q == 1'b0);
    wire edge_detected = (mode == 2'b01) ? rising_edge :
                        (mode == 2'b10) ? falling_edge :
                        (mode == 2'b11) ? (rising_edge | falling_edge) : 1'b0;
    
    assign pulse = edge_detected;
    assign cnt = cnt_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_reg <= 8'b0;
            sig_q <= 1'b0;
            sig_qq <= 1'b0;
        end else begin
            sig_q <= sig;
            sig_qq <= sig_q;
            
            if (edge_detected && (cnt_reg != 8'hFF)) begin
                cnt_reg <= cnt_reg + 1'b1;
            end
        end
    end

endmodule
