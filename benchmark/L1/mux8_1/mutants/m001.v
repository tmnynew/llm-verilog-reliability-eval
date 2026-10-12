// MUTANT m001 CRP line 10: "1'b0" -> "1'b1"
// Golden reference: parameterised 8-to-1 multiplexer with output enable
module mux8_1 #(
    parameter WIDTH = 4
) (
    input  [8*WIDTH-1:0] din,
    input  [2:0]         sel,
    input                en,
    output [WIDTH-1:0]   dout
);
    assign dout = en ? din[sel*WIDTH +: WIDTH] : {WIDTH{1'b1}};
endmodule
