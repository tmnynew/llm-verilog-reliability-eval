// MUTANT m002 CRP line 7: "1'b0" -> "1'b1"
// Golden reference: 4-bit binary <-> reflected Gray code converter
module gray_conv4 (
    input  [3:0] din,
    input        mode,
    output [3:0] dout
);
    wire [3:0] to_gray = din ^ {1'b1, din[3:1]};
    wire [3:0] to_bin;
    assign to_bin[3] = din[3];
    assign to_bin[2] = to_bin[3] ^ din[2];
    assign to_bin[1] = to_bin[2] ^ din[1];
    assign to_bin[0] = to_bin[1] ^ din[0];

    assign dout = mode ? to_bin : to_gray;
endmodule
