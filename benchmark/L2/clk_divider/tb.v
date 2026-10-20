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
module tb_clk_divider;
    reg        clk = 0, rst_n = 0;
    reg  [7:0] div = 8'd4;
    wire       tick, clk_out;

    clk_divider dut (.clk(clk), .rst_n(rst_n), .div(div), .tick(tick), .clk_out(clk_out));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i, j;
    // Latency-window consistency: the per-cycle WCHECK accepts either the zero-latency or the
    // one-cycle-delayed reference, so additionally each output must agree with *one* of the two
    // references over the whole run (mis_*0 == 0 or mis_*1 == 0).  This replaces aggregate
    // pulse/toggle counts, which legitimately differ between the two latencies when `div`
    // changes between edges.
    integer mis_tick0 = 0, mis_tick1 = 0, mis_clk0 = 0, mis_clk1 = 0;

    // ---- reference ----
    reg [7:0] rcnt = 0;
    reg       rtick = 0, rtick_d = 0, rclk_d = 0, rclk_dd = 0;
    wire      rclk = (rcnt < (div >> 1));
    always @(posedge clk) begin
        if (!rst_n) begin rcnt <= 0; rtick <= 0; rtick_d <= 0; rclk_d <= 1; rclk_dd <= 1; end
        else begin
            rtick_d <= rtick; rclk_d <= rclk; rclk_dd <= rclk_d;
            rtick <= (rcnt >= div - 1);
            rcnt  <= (rcnt >= div - 1) ? 0 : rcnt + 1;
        end
    end

    task step;
        begin
            cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 1'b0, tick)
            end else begin
                `WCHECK("timing", cyc, rtick, rtick_d, tick)
                `WCHECK("func", cyc, rclk, rclk_d, clk_out)
                if (tick    !== rtick)   mis_tick0 = mis_tick0 + 1;
                if (tick    !== rtick_d) mis_tick1 = mis_tick1 + 1;
                if (clk_out !== rclk)    mis_clk0  = mis_clk0 + 1;
                if (clk_out !== rclk_d)  mis_clk1  = mis_clk1 + 1;
            end
        end
    endtask

    task run;
        input integer n;
        begin for (j = 0; j < n; j = j + 1) begin @(negedge clk); step; end end
    endtask

    initial begin
        rst_n = 0; div = 4; run(3);
        rst_n = 1;
        run(40);                       // div = 4
        div = 2;  run(40);             // minimum ratio
        div = 3;  run(40);             // odd ratio
        div = 255; run(600);           // maximum ratio, two full periods
        div = 5;  run(3); div = 200; run(30); div = 6; run(60);   // decrease while cnt is large -> immediate wrap
        // mid-run reset
        rst_n = 0; run(2); rst_n = 1; run(20);
        // random ratios
        for (i = 0; i < 60; i = i + 1) begin
            div = 2 + (($random(seed) & 255) % 40);
            run(1 + ($random(seed) & 63));
        end
        div = 8; run(40);
        `CHECK("timing", 1, 1'b1, (mis_tick0 == 0 || mis_tick1 == 0))
        `CHECK("func",   2, 1'b1, (mis_clk0  == 0 || mis_clk1  == 0))
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
