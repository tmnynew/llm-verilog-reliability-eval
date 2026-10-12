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
            r     <= 32'd0;
            out_r <= 1'b0;
        end else if (in) begin
            r     <= LEN;
            out_r <= 1'b1;
        end else if (r > 32'd0) begin
            r     <= r - 32'd1;
            out_r <= 1'b1;
        end else begin
            r     <= 32'd0;
            out_r <= 1'b0;
        end
    end

    assign out = out_r;

endmodule
