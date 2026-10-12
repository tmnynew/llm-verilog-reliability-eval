// MUTANT m014 CRP line 16: "4'd9" -> "4'd10"
// Golden reference: one-digit BCD full adder with input validity flag
module bcd_adder (
    input  [3:0] a,
    input  [3:0] b,
    input        cin,
    output [3:0] sum,
    output       cout,
    output       invalid
);
    wire [4:0] bin = a + b + cin;          // 0..19 for valid inputs
    wire       ge10 = (bin > 5'd9);
    wire [4:0] adj = ge10 ? bin + 5'd6 : bin;

    assign sum     = adj[3:0];
    assign cout    = ge10;
    assign invalid = (a > 4'd9) | (b > 4'd10);
endmodule
