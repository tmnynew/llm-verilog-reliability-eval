// MUTANT m011 CRP line 30: "1'b0" -> "1'b1"
// Golden reference: counter-based debouncer, synchronous active-low reset
module debounce #(
    parameter STABLE_CYCLES = 16
) (
    input      clk,
    input      rst_n,
    input      btn_in,
    output reg btn_out
);
    // enough bits to count up to STABLE_CYCLES-1
    localparam CW = (STABLE_CYCLES <= 2)    ? 1 :
                    (STABLE_CYCLES <= 4)    ? 2 :
                    (STABLE_CYCLES <= 8)    ? 3 :
                    (STABLE_CYCLES <= 16)   ? 4 :
                    (STABLE_CYCLES <= 32)   ? 5 :
                    (STABLE_CYCLES <= 64)   ? 6 :
                    (STABLE_CYCLES <= 128)  ? 7 :
                    (STABLE_CYCLES <= 256)  ? 8 :
                    (STABLE_CYCLES <= 512)  ? 9 :
                    (STABLE_CYCLES <= 1024) ? 10 : 20;
    localparam [CW-1:0] LAST = STABLE_CYCLES - 1;

    reg [CW-1:0] cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            btn_out <= 1'b0;
            cnt     <= {CW{1'b0}};
        end else if (btn_in == btn_out) begin
            cnt <= {CW{1'b1}};
        end else if (cnt == LAST) begin
            btn_out <= btn_in;
            cnt     <= {CW{1'b0}};
        end else begin
            cnt <= cnt + 1'b1;
        end
    end
endmodule
