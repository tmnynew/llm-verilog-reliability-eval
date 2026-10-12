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

// Detect wrap condition
assign wrap_pulse = (q_reg == 4'b0001) && en;

// Sequential process for q and wrap
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        q_reg <= 4'b0001;
        wrap_reg <= 1'b0;
    end else begin
        // Update wrap register
        wrap_reg <= wrap_pulse;
        
        // Update q based on enable and direction
        if (en) begin
            if (dir) begin
                // Right shift (loop from LSB to MSB)
                q_reg <= {q_reg[0], q_reg[3:1]};
            end else begin
                // Left shift (loop from MSB to LSB)
                q_reg <= {q_reg[2:0], q_reg[3]};
            end
        end
    end
end

// Output assignment
assign q = q_reg;

endmodule
