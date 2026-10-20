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

// Generate the next state based on current state and control signals
wire [3:0] next_q;
assign next_q = dir ? {q_reg[0], q_reg[3:1]} : {q_reg[2:0], q_reg[3]};

// Detect wrap condition: when we transition from 4'b1000 to 4'b0001
wire wrap_pulse = (q_reg == 4'b1000) && (next_q == 4'b0001);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        q_reg <= 4'b0001;
        wrap_reg <= 1'b0;
    end else begin
        if (en) begin
            q_reg <= next_q;
            wrap_reg <= wrap_pulse;
        end else begin
            wrap_reg <= 1'b0;
        end
    end
end

assign q = q_reg;
assign wrap = wrap_reg;

endmodule
