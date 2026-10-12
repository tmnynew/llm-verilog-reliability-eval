// Cycle-level self-checking testbench with a 0..1 cycle latency window - see docs/testbench_protocol.md
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
`define WCHECK(_t, _id, _r, _rd, _g) \
    begin \
        n_checks = n_checks + 1; \
        if ((_g) !== (_r) && (_g) !== (_rd)) begin \
            n_fail = n_fail + 1; \
            if (n_fail <= 20) $display("TB_FAIL tag=%s case=%0d exp=%0h got=%0h", _t, _id, _r, _g); \
        end \
    end
module tb_ring_counter;
    reg  clk = 0, rst_n = 0, en = 0, dir = 0;
    wire [3:0] q;
    wire       wrap;

    ring_counter dut (.clk(clk), .rst_n(rst_n), .en(en), .dir(dir), .q(q), .wrap(wrap));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i, j;
    // Latency-window consistency: the per-cycle WCHECK accepts either the zero-latency or the
    // one-cycle-delayed reference for `wrap`, so additionally it must agree with *one* of the two
    // over the whole run (mis0 == 0 or mis1 == 0).  This replaces the aggregate pulse count,
    // which legitimately differs by one for a registered output around a reset.
    integer mis0 = 0, mis1 = 0;
    reg [3:0] rq = 4'b0001;
    reg       rwrap = 0, rwrap_d = 0;
    wire [3:0] rnext = !en ? rq : (dir ? {rq[0], rq[3:1]} : {rq[2:0], rq[3]});
    always @(posedge clk) begin
        if (!rst_n) begin rq <= 4'b0001; rwrap <= 0; rwrap_d <= 0; end
        else begin rwrap_d <= rwrap; rq <= rnext; rwrap <= en && (rnext == 4'b0001); end
    end

    task step;
        begin
            cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 4'b0001, q)
                `CHECK("reset", cyc, 1'b0, wrap)
            end else begin
                `CHECK("state", cyc, rq, q)
                `WCHECK("timing", cyc, rwrap, rwrap_d, wrap)
                if (wrap !== rwrap)   mis0 = mis0 + 1;
                if (wrap !== rwrap_d) mis1 = mis1 + 1;
            end
        end
    endtask

    task run;
        input integer n;
        begin for (j = 0; j < n; j = j + 1) begin @(negedge clk); step; end end
    endtask

    initial begin
        en = 1; dir = 1; run(3);              // active inputs during reset
        rst_n = 1;
        en = 1; dir = 0; run(9);              // two full left rotations + 1
        en = 0;          run(5);              // hold
        dir = 1; en = 1; run(9);              // right rotations
        en = 1; dir = 0; run(2); dir = 1; run(2); dir = 0; run(3);   // direction reversals
        rst_n = 0; run(2); rst_n = 1; run(4);
        for (i = 0; i < 3000; i = i + 1) begin @(negedge clk); step; en = $random(seed); dir = $random(seed); end
        en = 0; run(3);
        `CHECK("timing", 1, 1'b1, (mis0 == 0 || mis1 == 0))
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
`undef WCHECK
