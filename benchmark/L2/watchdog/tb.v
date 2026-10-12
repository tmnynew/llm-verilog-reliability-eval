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
module tb_watchdog;
    reg  clk = 0, rst_n = 0, enable = 0, kick = 0;
    wire to_a, to_b;

    watchdog                 dut_a (.clk(clk), .rst_n(rst_n), .enable(enable), .kick(kick), .timeout(to_a)); // TIMEOUT = 64
    watchdog #(.TIMEOUT(5))  dut_b (.clk(clk), .rst_n(rst_n), .enable(enable), .kick(kick), .timeout(to_b));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i, j;
    // Latency-window consistency: the per-cycle WCHECK accepts either the zero-latency or the
    // one-cycle-delayed reference, so additionally each output must agree with *one* of the two
    // references over the whole run (mis_*0 == 0 or mis_*1 == 0).  This replaces aggregate pulse
    // counts, which legitimately differ by one for a registered output around a reset.
    integer mis_a0 = 0, mis_a1 = 0, mis_b0 = 0, mis_b1 = 0;
    integer ca = 0, cb = 0;
    reg ra = 0, rb = 0, ra_d = 0, rb_d = 0;
    always @(posedge clk) begin
        if (!rst_n) begin ca <= 0; cb <= 0; ra <= 0; rb <= 0; ra_d <= 0; rb_d <= 0; end
        else begin
            ra_d <= ra; rb_d <= rb;
            if (!enable || kick) begin ca <= 0; ra <= 0; end
            else if (ca == 63) ra <= 1; else ca <= ca + 1;
            if (!enable || kick) begin cb <= 0; rb <= 0; end
            else if (cb == 4) rb <= 1; else cb <= cb + 1;
        end
    end

    task step;
        begin
            cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 1'b0, to_a)
                `CHECK("reset", cyc, 1'b0, to_b)
            end else begin
                `WCHECK("timing", cyc, ra, ra_d, to_a)
                `WCHECK("timing", cyc + 100000, rb, rb_d, to_b)
                if (to_a !== ra)   mis_a0 = mis_a0 + 1;
                if (to_a !== ra_d) mis_a1 = mis_a1 + 1;
                if (to_b !== rb)   mis_b0 = mis_b0 + 1;
                if (to_b !== rb_d) mis_b1 = mis_b1 + 1;
            end
        end
    endtask

    task run;
        input integer n;
        begin for (j = 0; j < n; j = j + 1) begin @(negedge clk); step; end end
    endtask

    initial begin
        enable = 1; kick = 0; run(3);
        rst_n = 1;
        run(70);                                  // no kick: dut_b times out after 5, dut_a after 64
        kick = 1; run(1); kick = 0; run(4);       // kick clears both; dut_b needs 5 quiet edges
        run(1); run(3);                           // b times out again
        enable = 0; run(3); enable = 1; run(63);  // a: exactly one edge short of timeout
        kick = 1; run(1); kick = 0; run(64);      // a times out at the 64th quiet edge
        kick = 1; run(2); kick = 0;
        for (i = 0; i < 20; i = i + 1) begin run(4); kick = 1; run(1); kick = 0; end   // regular feeding, never times out
        rst_n = 0; run(2); rst_n = 1;
        for (i = 0; i < 4000; i = i + 1) begin
            @(negedge clk); step;
            kick   = (($random(seed) & 15) == 0);
            enable = (($random(seed) & 255) != 0) ? enable : ~enable;
        end
        kick = 0; enable = 1; run(70);
        `CHECK("func", 1, 1'b1, (mis_a0 == 0 || mis_a1 == 0))
        `CHECK("func", 2, 1'b1, (mis_b0 == 0 || mis_b1 == 0))
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
