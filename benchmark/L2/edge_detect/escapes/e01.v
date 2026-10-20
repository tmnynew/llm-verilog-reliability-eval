module edge_detect (
    input clk,
    input rst_n,
    input sig,
    input [1:0] mode,
    output pulse,
    output [7:0] cnt
);

    reg sig_d;
    reg rise;
    reg fall;
    reg pulse_r;
    reg [7:0] cnt_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            sig_d   <= 1'b0;
            rise    <= 1'b0;
            fall    <= 1'b0;
            pulse_r <= 1'b0;
            cnt_r   <= 8'd0;
        end else begin
            sig_d   <= sig;
            rise    <= sig & ~sig_d;
            fall    <= ~sig & sig_d;
            pulse_r <= (rise & mode[0]) | (fall & mode[1]);
            if ((rise & mode[0]) | (fall & mode[1]))
                cnt_r <= cnt_r + 8'd1;
        end
    end

    assign pulse = pulse_r;
    assign cnt   = cnt_r;

endmodule
