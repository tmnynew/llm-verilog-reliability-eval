// MUTANT m003 URO line 12: '~' -> ''
// Golden reference: configurable edge detector with event counter
module edge_detect (
    input            clk,
    input            rst_n,
    input            sig,
    input      [1:0] mode,
    output reg       pulse,
    output reg [7:0] cnt
);
    reg  sig_d;
    wire rise = sig & ~sig_d;
    wire fall = sig & sig_d;
    wire det  = (mode[0] & rise) | (mode[1] & fall);

    always @(posedge clk) begin
        if (!rst_n) begin
            sig_d <= 1'b0;
            pulse <= 1'b0;
            cnt   <= 8'd0;
        end else begin
            sig_d <= sig;
            pulse <= det;
            if (det)
                cnt <= cnt + 8'd1;
        end
    end
endmodule
