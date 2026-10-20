module ring_counter (
    input clk,
    input rst_n,
    input en,
    input dir,
    output [3:0] q,
    output wrap
);

    reg [3:0] q_reg;
    reg wrap_reg;
    
    assign q = q_reg;
    assign wrap = wrap_reg;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            q_reg <= 4'b0001;
            wrap_reg <= 1'b0;
        end
        else begin
            if (en) begin
                if (dir) begin
                    // Right shift: 0001->1000->0100->0010->0001
                    case (q_reg)
                        4'b0001: q_reg <= 4'b1000;
                        4'b1000: q_reg <= 4'b0100;
                        4'b0100: q_reg <= 4'b0010;
                        4'b0010: q_reg <= 4'b0001;
                        default: q_reg <= 4'b0001;
                    endcase
                end
                else begin
                    // Left shift: 0001->0010->0100->1000->0001
                    case (q_reg)
                        4'b0001: q_reg <= 4'b0010;
                        4'b0010: q_reg <= 4'b0100;
                        4'b0100: q_reg <= 4'b1000;
                        4'b1000: q_reg <= 4'b0001;
                        default: q_reg <= 4'b0001;
                    endcase
                end
            end
            
            // Update wrap signal - set to 1 when q becomes 4'b0001 due to an enabled transition
            if (!rst_n) begin
                wrap_reg <= 1'b0;
            end
            else begin
                if (en && (q_reg == 4'b0001)) begin
                    wrap_reg <= 1'b1;
                end
                else begin
                    wrap_reg <= 1'b0;
                end
            end
        end
    end

endmodule
