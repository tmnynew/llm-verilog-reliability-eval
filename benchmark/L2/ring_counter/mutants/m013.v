// MUTANT m013 ROR line 18: '==' -> '!='
// Golden reference: 4-bit bidirectional one-hot ring counter with wrap pulse
module ring_counter (
    input            clk,
    input            rst_n,
    input            en,
    input            dir,
    output reg [3:0] q,
    output reg       wrap
);
    wire [3:0] q_next = !en ? q : (dir ? {q[0], q[3:1]} : {q[2:0], q[3]});

    always @(posedge clk) begin
        if (!rst_n) begin
            q    <= 4'b0001;
            wrap <= 1'b0;
        end else begin
            q    <= q_next;
            wrap <= en && (q_next != 4'b0001);
        end
    end
endmodule
