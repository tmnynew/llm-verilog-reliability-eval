module ring_counter (
    input clk,
    input rst_n,
    input en,
    input dir,
    output [3:0] q,
    output wrap
);

    reg [3:0] q_r;
    reg       wrap_r;

    // 下一拍 q 值
    wire [3:0] q_next = (~rst_n) ? 4'b0001 :
                        (en & ~dir) ? {q_r[2:0], q_r[3]} :
                        (en &  dir) ? {q_r[0], q_r[3:1]} :
                        q_r;

    // 下一拍 wrap：en=1 且下一拍 q 变为 0001
    wire wrap_next = (en & (q_next == 4'b0001));

    always @(posedge clk) begin
        q_r    <= q_next;
        wrap_r <= wrap_next;
    end

    assign q    = q_r;
    assign wrap = wrap_r;

endmodule
