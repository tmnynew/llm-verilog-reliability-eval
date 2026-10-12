// MUTANT m001 WID line 21: '1' -> '2'
// Golden reference: retriggerable pulse stretcher
module pulse_stretch #(
    parameter LEN = 8
) (
    input  clk,
    input  rst_n,
    input  in,
    output out
);
    localparam CW = (LEN <= 1)    ? 1 :
                    (LEN <= 3)    ? 2 :
                    (LEN <= 7)    ? 3 :
                    (LEN <= 15)   ? 4 :
                    (LEN <= 31)   ? 5 :
                    (LEN <= 63)   ? 6 :
                    (LEN <= 127)  ? 7 :
                    (LEN <= 255)  ? 8 :
                    (LEN <= 511)  ? 9 :
                    (LEN <= 1023) ? 10 : 20;

    reg [CW-2:0] remaining;

    always @(posedge clk) begin
        if (!rst_n)
            remaining <= {CW{1'b0}};
        else if (in)
            remaining <= LEN[CW-1:0];
        else if (remaining != {CW{1'b0}})
            remaining <= remaining - 1'b1;
    end

    assign out = (remaining != {CW{1'b0}});
endmodule
