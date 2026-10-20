// MUTANT m001 WID line 9: '7' -> '6'
// Golden reference: programmable integer clock divider with tick pulse
module clk_divider (
    input        clk,
    input        rst_n,
    input  [7:0] div,
    output reg   tick,
    output       clk_out
);
    reg  [6:0] cnt;
    wire       last = (cnt >= div - 8'd1);

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt  <= 8'd0;
            tick <= 1'b0;
        end else begin
            cnt  <= last ? 8'd0 : cnt + 8'd1;
            tick <= last;
        end
    end

    assign clk_out = (cnt < (div >> 1));
endmodule
