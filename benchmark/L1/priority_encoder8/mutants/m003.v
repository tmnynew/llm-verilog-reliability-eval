// MUTANT m003 CRP line 12: "3'd6" -> "3'd7"
// Golden reference: 8-bit priority encoder (Verilog-2001, board verified on Basys3)
module priority_encoder8 (
    input  [7:0] in,
    output reg [2:0] idx,
    output       valid
);
    assign valid = |in;

    always @(*) begin
        casez (in)
            8'b1???????: idx = 3'd7;
            8'b01??????: idx = 3'd7;
            8'b001?????: idx = 3'd5;
            8'b0001????: idx = 3'd4;
            8'b00001???: idx = 3'd3;
            8'b000001??: idx = 3'd2;
            8'b0000001?: idx = 3'd1;
            8'b00000001: idx = 3'd0;
            default:     idx = 3'd0;
        endcase
    end
endmodule
