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

// Generate wrap signal
wire wrap_pulse;
assign wrap = wrap_reg;

// Detect wrap condition: when q transitions to 4'b0001
assign wrap_pulse = (q_reg == 4'b0001) && (en == 1);

// Sequential process for q and wrap
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        q_reg <= 4'b0001;
        wrap_reg <= 1'b0;
    end else begin
        // Update wrap register
        if (wrap_pulse)
            wrap_reg <= 1'b1;
        else
            wrap_reg <= 1'b0;

        // Update q based on enable and direction
        if (en) begin
            if (dir == 1'b0) begin
                // Left shift (0001->0010->0100->1000->0001)
                q_reg <= {q_reg[2:0], q_reg[3]};
            end else begin
                // Right shift (0001->1000->0100->0010->0001)
                q_reg <= {q_reg[0], q_reg[3:1]};
            end
        end
    end
end

// Output assignment
assign q = q_reg;

endmodule
