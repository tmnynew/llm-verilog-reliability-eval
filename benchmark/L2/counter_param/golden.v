// Golden reference: parameterised modulo-N up counter, synchronous active-low reset
module counter_param #(
    parameter WIDTH = 8,
    parameter MOD   = 200
) (
    input                  clk,
    input                  rst_n,
    input                  en,
    output reg [WIDTH-1:0] count,
    output                 tc
);
    // MOD-1 expressed at WIDTH bits so that the comparison has matching widths.
    localparam [WIDTH-1:0] LAST = MOD - 1;

    assign tc = en && (count == LAST);

    always @(posedge clk) begin
        if (!rst_n)
            count <= {WIDTH{1'b0}};
        else if (en) begin
            if (count == LAST)
                count <= {WIDTH{1'b0}};
            else
                count <= count + 1'b1;
        end
    end
endmodule
