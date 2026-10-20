// Transaction-level testbench for the byte-copy DMA: synchronous memory model, sequential-copy reference, address/ordering monitor
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

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, k, cyc = 0;
    always @(negedge clk) cyc = cyc + 1;

    // synchronous single-port memory model
    reg [7:0] mem [0:255];
    reg [7:0] model [0:255];
    always @(posedge clk) begin
        if (mem_re === 1'b1) mem_rdata <= mem[mem_addr];
        if (mem_we === 1'b1) mem[mem_addr] <= mem_wdata;
    end

    // monitor
    integer   we_cnt = 0, re_cnt = 0, bad_addr = 0, done_cnt = 0, wide = 0, order_bad = 0;
    reg [7:0] cur_src = 0, cur_dst = 0, cur_len = 0;
    reg       done_p = 0;
    always @(negedge clk) if (rst_n) begin
        if (mem_we === 1'b1) begin
            if (((mem_addr - cur_dst) & 8'hFF) >= cur_len) bad_addr = bad_addr + 1;
            if (we_cnt >= re_cnt) order_bad = order_bad + 1;        // i-th write before i-th read completed
            we_cnt = we_cnt + 1;
        end
        if (mem_re === 1'b1) begin
            if (((mem_addr - cur_src) & 8'hFF) >= cur_len) bad_addr = bad_addr + 1;
            re_cnt = re_cnt + 1;
        end
        if (done === 1'b1) begin done_cnt = done_cnt + 1; if (done_p === 1'b1) wide = wide + 1; end
        if (done_p === 1'b1 && busy !== 1'b0) begin
            // busy may still be 1 in the done cycle but must be 0 one cycle later
            if (done !== 1'b1) wide = wide + 1;
        end
        done_p = done;
    end else done_p = 0;

    task dma;
        input [7:0] s, d, l;
        input integer id;
        integer t0, mism;
        begin
            for (k = 0; k < 256; k = k + 1) model[k] = mem[k];
            for (k = 0; k < l; k = k + 1) model[(d + k) & 8'hFF] = model[(s + k) & 8'hFF];
            @(negedge clk); src = s; dst = d; len = l; start = 1;
            cur_src = s; cur_dst = d; cur_len = l; we_cnt = 0; re_cnt = 0; bad_addr = 0; order_bad = 0; done_cnt = 0;
            @(negedge clk); start = 0; src = ~s; dst = ~d; len = ~l;
            t0 = cyc;
            if (l != 0) `CHECK("proto", id * 10 + 1, 1'b1, busy)
            while (busy === 1'b1 && cyc - t0 < 4 * l + 8) @(negedge clk);
            `CHECK("timing", id * 10 + 2, 1'b0, busy)
            @(negedge clk); @(negedge clk);
            `CHECK("proto", id * 10 + 3, 1, done_cnt)
            `CHECK("proto", id * 10 + 4, l, we_cnt)
            `CHECK("proto", id * 10 + 5, l, re_cnt)
            `CHECK("proto", id * 10 + 6, 0, bad_addr)
            `CHECK("proto", id * 10 + 7, 0, order_bad)
            mism = 0;
            for (k = 0; k < 256; k = k + 1) if (mem[k] !== model[k]) mism = mism + 1;
            `CHECK("func", id * 10 + 8, 0, mism)
        end
    endtask

    initial begin
        for (k = 0; k < 256; k = k + 1) mem[k] = $random(seed);
        rst_n = 0; start = 1; len = 8'd5;
        repeat (3) @(negedge clk);
        `CHECK("reset", 1, 1'b0, busy)
        `CHECK("reset", 2, 1'b0, done)
        `CHECK("reset", 3, 1'b0, mem_we)
        `CHECK("reset", 4, 1'b0, mem_re)
        start = 0; rst_n = 1;
        repeat (3) @(negedge clk);
        `CHECK("reset", 5, 1'b0, busy)

        dma(8'd10, 8'd20, 8'd2, 1);
        dma(8'd0, 8'd128, 8'd1, 2);
        dma(8'd0, 8'd100, 8'd0, 3);            // len = 0
        dma(8'd40, 8'd40, 8'd8, 4);            // same address
        dma(8'd10, 8'd8, 8'd6, 5);             // overlap, dst < src
        dma(8'd8, 8'd10, 8'd6, 6);             // overlap, dst > src (forward-copy semantics)
        dma(8'd250, 8'd3, 8'd10, 7);           // source wraps
        dma(8'd3, 8'd250, 8'd10, 8);           // destination wraps
        dma(8'd0, 8'd1, 8'd255, 9);            // maximal length, heavy overlap
        for (i = 0; i < 10; i = i + 1) dma($random(seed), $random(seed), {$random(seed)} % 40, 10 + i);

        // start while busy is ignored
        for (k = 0; k < 256; k = k + 1) model[k] = mem[k];
        for (k = 0; k < 30; k = k + 1) model[(200 + k) & 8'hFF] = model[(50 + k) & 8'hFF];
        @(negedge clk); src = 50; dst = 200; len = 30; start = 1; done_cnt = 0;
        cur_src = 50; cur_dst = 200; cur_len = 30; we_cnt = 0; re_cnt = 0; bad_addr = 0;
        @(negedge clk); start = 0;
        repeat (7) @(negedge clk);
        src = 0; dst = 0; len = 3; start = 1; @(negedge clk); start = 0;
        while (busy === 1'b1) @(negedge clk);
        repeat (2) @(negedge clk);
        `CHECK("proto", 100, 1, done_cnt)
        `CHECK("proto", 101, 30, we_cnt)
        `CHECK("proto", 102, 0, bad_addr)
        k = 0; for (i = 0; i < 256; i = i + 1) if (mem[i] !== model[i]) k = k + 1;
        `CHECK("func", 103, 0, k)
        repeat (20) @(negedge clk);
        `CHECK("proto", 104, 1, done_cnt)

        // reset in the middle of a transfer
        @(negedge clk); src = 0; dst = 100; len = 80; start = 1;
        cur_src = 0; cur_dst = 100; cur_len = 80;
        @(negedge clk); start = 0;
        repeat (15) @(negedge clk);
        rst_n = 0; done_cnt = 0;
        repeat (2) @(negedge clk);
        `CHECK("reset", 110, 1'b0, busy)
        `CHECK("reset", 111, 1'b0, mem_we)
        `CHECK("reset", 112, 1'b0, mem_re)
        rst_n = 1;
        repeat (4) @(negedge clk);
        `CHECK("reset", 113, 0, done_cnt)
        dma(8'd7, 8'd77, 8'd7, 120);
        `CHECK("proto", 130, 0, wide)
        if (n_fail == 0) $display("TB_RESULT PASS n_checks=%0d", n_checks);
        else             $display("TB_RESULT FAIL n_fail=%0d n_checks=%0d", n_fail, n_checks);
        $finish;
    end

    initial begin
        #2000000;
        $display("TB_FAIL tag=crash case=0 exp=0 got=0");
        $display("TB_RESULT FAIL n_fail=1 n_checks=%0d", n_checks);
        $finish;
    end
endmodule
`undef CHECK
