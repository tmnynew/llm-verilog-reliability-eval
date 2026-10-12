// Weak testbench (Exp. 2 baseline): one 4-byte copy with a simple memory model; waits for busy to fall, then
// compares only the destination bytes and expects a done pulse. No len = 0, no overlap or address wrap, no
// address/ordering monitor, no second transfer, no start while busy, no mid-transfer reset, no whole-memory
// compare - see docs/testbench_protocol.md
`timescale 1ns/1ps
`ifndef SEED
`define SEED 1
`endif
`define CHECK(_t, _id, _e, _g) \
    begin \
        n_checks = n_checks + 1; \
        if ((_e) !== (_g)) begin \
            n_fail = n_fail + 1; \
            if (n_fail <= 20) $display("TB_FAIL tag=%s case=%0d exp=%0h got=%0h", _t, _id, _e, _g); \
        end \
    end
module tb_simple_dma;
    reg        clk = 0, rst_n = 0, start = 0;
    reg  [7:0] src = 0, dst = 0, len = 0;
    wire       busy, done, mem_we, mem_re;
    wire [7:0] mem_addr, mem_wdata;
    reg  [7:0] mem_rdata = 0;

    simple_dma dut (.clk(clk), .rst_n(rst_n), .start(start), .src(src), .dst(dst), .len(len), .busy(busy), .done(done),
                    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, k, t, done_cnt = 0;

    reg [7:0] mem [0:255];
    always @(posedge clk) begin
        if (mem_re === 1'b1) mem_rdata <= mem[mem_addr];
        if (mem_we === 1'b1) mem[mem_addr] <= mem_wdata;
    end
    always @(negedge clk) if (done === 1'b1) done_cnt = done_cnt + 1;

    initial begin
        for (k = 0; k < 256; k = k + 1) mem[k] = k ^ 8'h5C;
        rst_n = 0; start = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);

        src = 8'd10; dst = 8'd20; len = 8'd4; start = 1; done_cnt = 0;
        @(negedge clk); start = 0;
        t = 0;
        while (busy === 1'b1 && t < 100) begin @(negedge clk); t = t + 1; end
        `CHECK("timing", 1, 1'b0, busy)
        repeat (2) @(negedge clk);
        `CHECK("proto", 2, 1, done_cnt)
        for (k = 0; k < 4; k = k + 1) `CHECK("func", 10 + k, ((10 + k) ^ 8'h5C), mem[20 + k])
        if (n_fail == 0) $display("TB_RESULT PASS n_checks=%0d", n_checks);
        else             $display("TB_RESULT FAIL n_fail=%0d n_checks=%0d", n_fail, n_checks);
        $finish;
    end

    initial begin
        #200000;
        $display("TB_FAIL tag=crash case=0 exp=0 got=0");
        $display("TB_RESULT FAIL n_fail=1 n_checks=%0d", n_checks);
        $finish;
    end
endmodule
`undef CHECK
