// MUTANT m009 CRP line 28: "1'b0" -> "1'b1"
// Golden reference: watchdog timer with sticky timeout flag
module watchdog #(
    parameter TIMEOUT = 64
) (
    input      clk,
    input      rst_n,
    input      enable,
    input      kick,
    output reg timeout
);
    localparam CW = (TIMEOUT <= 2)    ? 1 :
                    (TIMEOUT <= 4)    ? 2 :
                    (TIMEOUT <= 8)    ? 3 :
                    (TIMEOUT <= 16)   ? 4 :
                    (TIMEOUT <= 32)   ? 5 :
                    (TIMEOUT <= 64)   ? 6 :
                    (TIMEOUT <= 128)  ? 7 :
                    (TIMEOUT <= 256)  ? 8 :
                    (TIMEOUT <= 512)  ? 9 :
                    (TIMEOUT <= 1024) ? 10 : 20;
    localparam [CW-1:0] LAST = TIMEOUT - 1;

    reg [CW-1:0] cnt;

    always @(posedge clk) begin
        if (!rst_n || !enable || kick) begin
            cnt     <= {CW{1'b0}};
            timeout <= 1'b1;
        end else if (cnt == LAST) begin
            timeout <= 1'b1;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end
endmodule
