module ring_counter (
    input clk,
    input rst_n,
    input en,
    input dir,
    output [3:0] q,
    output wrap
);
    reg [3:0] q_reg;
    reg       wrap_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            q_reg <= 4'b0001;
        end else if (en) begin
            if (dir == 1'b0)
                q_reg <= {q_reg[2:0], q_reg[3]};
            else
                q_reg <= {q_reg[0], q_reg[3:1]};
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wrap_reg <= 1'b0;
        end else begin
            wrap_reg <= en && (q_reg == 4'b0001);
        end
    end

    assign q    = q_reg;
    assign wrap = wrap_reg;
endmodule
