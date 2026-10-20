module edge_detect (
    input clk,
    input rst_n,
    input sig,
    input [1:0] mode,
    output pulse,
    output [7:0] cnt
);

    reg [7:0] cnt_reg;
    reg sig_d1, sig_d2;
    reg pulse_reg;

    wire pos_edge = ~sig_d2 & sig_d1;
    wire neg_edge = sig_d2 & ~sig_d1;
    wire any_edge = pos_edge | neg_edge;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt_reg <= 8'b0;
            sig_d1 <= 1'b0;
            sig_d2 <= 1'b0;
            pulse_reg <= 1'b0;
        end else begin
            sig_d1 <= sig;
            sig_d2 <= sig_d1;
            
            case (mode)
                2'b00: pulse_reg <= 1'b0; // no detection
                2'b01: pulse_reg <= pos_edge; // rising edge only
                2'b10: pulse_reg <= neg_edge; // falling edge only
                2'b11: pulse_reg <= any_edge; // both edges
                default: pulse_reg <= 1'b0;
            endcase
            
            if (pulse_reg) begin
                cnt_reg <= cnt_reg + 1'b1;
            end
        end
    end

    assign pulse = pulse_reg;
    assign cnt = cnt_reg;

endmodule
