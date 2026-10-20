// MUTANT m012 ROR line 24: '==' -> '!='
// Golden reference: 8-bit universal shift register
module shift_reg (
    input            clk,
    input            rst_n,
    input      [1:0] mode,
    input      [7:0] d_in,
    input            s_in,
    output reg [7:0] q,
    output           s_out
);
    always @(posedge clk) begin
        if (!rst_n)
            q <= 8'd0;
        else
            case (mode)
                2'b00:   q <= q;
                2'b01:   q <= {q[6:0], s_in};
                2'b10:   q <= {s_in, q[7:1]};
                default: q <= d_in;
            endcase
    end

    assign s_out = (mode == 2'b01) ? q[7] :
                   (mode != 2'b10) ? q[0] : 1'b0;
endmodule
