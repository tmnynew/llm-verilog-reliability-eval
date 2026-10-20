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

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt_reg <= 8'b0;
            sig_d1 <= 1'b0;
            sig_d2 <= 1'b0;
            pulse_reg <= 1'b0;
        end else begin
            sig_d1 <= sig;
            sig_d2 <= sig_d1;
            
            if (pulse_reg) begin
                cnt_reg <= cnt_reg + 1'b1;
            end
            
            pulse_reg <= 1'b0;
            
            case (mode)
                2'b00: begin // no detection
                    pulse_reg <= 1'b0;
                end
                2'b01: begin // rising edge
                    if (sig_d1 & ~sig_d2) begin
                        pulse_reg <= 1'b1;
                    end
                end
                2'b10: begin // falling edge
                    if (~sig_d1 & sig_d2) begin
                        pulse_reg <= 1'b1;
                    end
                end
                2'b11: begin // both edges
                    if ((sig_d1 & ~sig_d2) | (~sig_d1 & sig_d2)) begin
                        pulse_reg <= 1'b1;
                    end
                end
                default: begin
                    pulse_reg <= 1'b0;
                end
            endcase
        end
    end

    assign pulse = pulse_reg;
    assign cnt = cnt_reg;

endmodule
