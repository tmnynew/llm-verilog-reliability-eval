// Cycle-level self-checking testbench with a 0..1 cycle latency window
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
module tb_edge_detect;
    reg        clk = 0, rst_n = 0, sig = 0;
    reg  [1:0] mode = 2'b11;
    wire       pulse;
    wire [7:0] cnt;

    edge_detect dut (.clk(clk), .rst_n(rst_n), .sig(sig), .mode(mode), .pulse(pulse), .cnt(cnt));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i, j;
    // Latency-window consistency: the per-cycle WCHECK accepts either the zero-latency or the
    // one-cycle-delayed reference, so additionally each output must agree with *one* of the two
    // references over the whole run (mis_*0 == 0 or mis_*1 == 0).  This replaces the aggregate
    // pulse count, which legitimately differs by one for a registered output around a reset.
    integer mis_p0 = 0, mis_p1 = 0, mis_c0 = 0, mis_c1 = 0;
    reg       rs = 0, rpulse = 0, rpulse_d = 0;
    reg [7:0] rcnt = 0, rcnt_d = 0;
    wire rdet = (mode[0] & sig & ~rs) | (mode[1] & ~sig & rs);
    always @(posedge clk) begin
        if (!rst_n) begin rs <= 0; rpulse <= 0; rpulse_d <= 0; rcnt <= 0; rcnt_d <= 0; end
        else begin rpulse_d <= rpulse; rcnt_d <= rcnt; rs <= sig; rpulse <= rdet; if (rdet) rcnt <= rcnt + 1; end
    end

    task step;
        begin
            cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 1'b0, pulse)
                `CHECK("reset", cyc, 8'd0, cnt)
            end else begin
                `WCHECK("timing", cyc, rpulse, rpulse_d, pulse)
                `WCHECK("func", cyc, rcnt, rcnt_d, cnt)
                if (pulse !== rpulse)   mis_p0 = mis_p0 + 1;
                if (pulse !== rpulse_d) mis_p1 = mis_p1 + 1;
                if (cnt !== rcnt)       mis_c0 = mis_c0 + 1;
                if (cnt !== rcnt_d)     mis_c1 = mis_c1 + 1;
            end
        end
    endtask

    task run;
        input integer n;
        begin for (j = 0; j < n; j = j + 1) begin @(negedge clk); step; end end
    endtask

    initial begin
        sig = 1; mode = 2'b11; run(3);           // sig high during reset -> first edge after release counts
        rst_n = 1; run(3);
        sig = 0; run(2); sig = 1; run(2); sig = 0; run(2);     // both edges
        mode = 2'b01; sig = 1; run(2); sig = 0; run(2); sig = 1; run(2);   // rising only
        mode = 2'b10; sig = 0; run(2); sig = 1; run(2); sig = 0; run(2);   // falling only
        mode = 2'b00; sig = 1; run(2); sig = 0; run(2);                    // disabled
        mode = 2'b11;
        for (i = 0; i < 600; i = i + 1) begin @(negedge clk); step; sig = ~sig; end   // toggle every cycle -> cnt wraps past 255
        rst_n = 0; run(2); rst_n = 1;
        for (i = 0; i < 3000; i = i + 1) begin @(negedge clk); step; sig = $random(seed); if (($random(seed) & 31) == 0) mode = $random(seed); end
        run(3);
        `CHECK("timing", 1, 1'b1, (mis_p0 == 0 || mis_p1 == 0))
        `CHECK("func",   2, 1'b1, (mis_c0 == 0 || mis_c1 == 0))
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
