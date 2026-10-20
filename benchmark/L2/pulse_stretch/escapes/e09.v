module pulse_stretch #(parameter LEN = 8) (
    input clk,
    input rst_n,
    input in,
    output out
);

    reg [31:0] r;
    reg out_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            r <= 0;
            out_r <= 1'b0;
        end else begin
            if (in)
                r <= LEN;
            else if (r != 0)
                r <= r - 1'b1;
            out_r <= (in | (r != 0));
        end
    end

    assign out = out_r;

endmodule
