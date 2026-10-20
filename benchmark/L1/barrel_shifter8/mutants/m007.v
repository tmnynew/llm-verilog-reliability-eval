// MUTANT m007 DDL line 16: 'default: dout = din;' -> '/* default removed */'
// Golden reference: 8-bit barrel shifter (logical left/right, arithmetic right, rotate left)
module barrel_shifter8 (
    input  [7:0] din,
    input  [2:0] shamt,
    input  [1:0] mode,
    output reg [7:0] dout
);
    wire [15:0] rot = {din, din} << shamt;  // rotate-left via doubled operand

    always @(*) begin
        case (mode)
            2'b00:   dout = din << shamt;
            2'b01:   dout = din >> shamt;
            2'b10:   dout = $signed(din) >>> shamt;
            2'b11:   dout = rot[15:8];
            /* default removed */
        endcase
    end
endmodule
