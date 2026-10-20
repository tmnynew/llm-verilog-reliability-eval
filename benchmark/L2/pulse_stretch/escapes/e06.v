module pulse_stretch #(parameter LEN = 8) (
    input clk,
    input rst_n,
    input in,
    output out
);
    reg [31:0] R;
    reg out_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            R <= 0;
            out_reg <= 1'b0;
        end else begin
            if (in) begin
                R <= LEN;
            end else if (R > 0) begin
                R <= R - 1;
            end
            out_reg <= (in || (R > 0));
        end
    end

    assign out = out_reg;
endmodule
