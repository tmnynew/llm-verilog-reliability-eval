// MUTANT m004 CRP line 12: "4'd1" -> "4'd2"
// Golden reference: 8-bit leading-zero counter
module lzc8 (
    input  [7:0] din,
    output reg [3:0] count,
    output       zero
);
    assign zero = (din == 8'd0);

    always @(*) begin
        casez (din)
            8'b1???_????: count = 4'd0;
            8'b01??_????: count = 4'd2;
            8'b001?_????: count = 4'd2;
            8'b0001_????: count = 4'd3;
            8'b0000_1???: count = 4'd4;
            8'b0000_01??: count = 4'd5;
            8'b0000_001?: count = 4'd6;
            8'b0000_0001: count = 4'd7;
            default:      count = 4'd8;
        endcase
    end
endmodule
