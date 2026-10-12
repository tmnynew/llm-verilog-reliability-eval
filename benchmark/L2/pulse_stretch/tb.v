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
module tb_pulse_stretch;
    reg  clk = 0, rst_n = 0, in = 0;
    wire out_a, out_b;

    pulse_stretch              dut_a (.clk(clk), .rst_n(rst_n), .in(in), .out(out_a)); // LEN = 8
    pulse_stretch #(.LEN(3))   dut_b (.clk(clk), .rst_n(rst_n), .in(in), .out(out_b));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i, j;
    // Latency-window consistency: the per-cycle WCHECK accepts either the zero-latency or the
    // one-cycle-delayed reference, so additionally each output must agree with *one* of the two
    // references over the whole run (mis_*0 == 0 or mis_*1 == 0).  This replaces aggregate pulse
    // counts, which legitimately differ by one for a registered output around a reset.
    integer mis_a0 = 0, mis_a1 = 0, mis_b0 = 0, mis_b1 = 0;
    integer ra = 0, rb = 0;
    reg  oa_d = 0, ob_d = 0;
    wire oa = (ra != 0), ob = (rb != 0);
    always @(posedge clk) begin
        if (!rst_n) begin ra <= 0; rb <= 0; oa_d <= 0; ob_d <= 0; end
        else begin
            oa_d <= oa; ob_d <= ob;
            if (in) ra <= 8; else if (ra != 0) ra <= ra - 1;
            if (in) rb <= 3; else if (rb != 0) rb <= rb - 1;
        end
    end

    task step;
        begin
            cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 1'b0, out_a)
                `CHECK("reset", cyc, 1'b0, out_b)
            end else begin
                `WCHECK("timing", cyc, oa, oa_d, out_a)
                `WCHECK("timing", cyc + 100000, ob, ob_d, out_b)
                if (out_a !== oa)   mis_a0 = mis_a0 + 1;
                if (out_a !== oa_d) mis_a1 = mis_a1 + 1;
                if (out_b !== ob)   mis_b0 = mis_b0 + 1;
                if (out_b !== ob_d) mis_b1 = mis_b1 + 1;
            end
        end
    endtask

    task run;
        input integer n;
        begin for (j = 0; j < n; j = j + 1) begin @(negedge clk); step; end end
    endtask

    initial begin
        in = 1; run(3);                                   // input during reset must not latch
        rst_n = 1; in = 0; run(3);
        in = 1; run(1); in = 0; run(12);                  // single-cycle pulse -> 8 / 3 cycles
        in = 1; run(5); in = 0; run(12);                  // long pulse
        in = 1; run(1); in = 0; run(2); in = 1; run(1); in = 0; run(12);   // retrigger inside window (b: gap of 2 < 3)
        in = 1; run(1); in = 0; run(7); in = 1; run(1); in = 0; run(12);   // retrigger at the last cycle of a's window
        in = 1; run(1); in = 0; run(8); in = 1; run(1); in = 0; run(12);   // separate pulses for a
        rst_n = 0; in = 1; run(2); rst_n = 1; in = 0; run(10);            // reset while stretching
        for (i = 0; i < 4000; i = i + 1) begin @(negedge clk); step; in = (($random(seed) & 7) == 0); end
        in = 0; run(12);
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
