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
module tb_pwm_gen;
    reg        clk = 0, rst_n = 0;
    reg  [7:0] duty = 0;
    wire       pwm;

    pwm_gen dut (.clk(clk), .rst_n(rst_n), .duty(duty), .pwm(pwm));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i, j;
    // Latency-window consistency: the per-cycle WCHECK accepts either the zero-latency (rpwm) or
    // the one-cycle-delayed (rpwm_d) reference, so additionally the output must agree with *one*
    // of them over the whole run (mis0 == 0 or mis1 == 0).  Aggregate high-cycle / edge counts
    // are not used: a registered output legitimately loses one high cycle at a reset.
    integer mis0 = 0, mis1 = 0;

    reg [7:0] rcnt = 0, rduty = 0;
    reg       rpwm_d = 0;
    wire      rpwm = (rcnt < rduty);
    always @(posedge clk) begin
        if (!rst_n) begin rcnt <= 0; rduty <= 0; rpwm_d <= 0; end
        else begin
            rpwm_d <= rpwm;
            rcnt <= rcnt + 1;
            if (rcnt == 255) rduty <= duty;
        end
    end

    task step;
        begin
            cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 1'b0, pwm)
            end else begin
                `WCHECK("func", cyc, rpwm, rpwm_d, pwm)
                if (pwm !== rpwm)   mis0 = mis0 + 1;
                if (pwm !== rpwm_d) mis1 = mis1 + 1;
            end
        end
    endtask

    task run;
        input integer n;
        begin for (j = 0; j < n; j = j + 1) begin @(negedge clk); step; end end
    endtask

    initial begin
        rst_n = 0; duty = 8'd100; run(3);
        rst_n = 1;
        run(256);                 // first period: latched duty is 0
        duty = 3;   run(256);     // 3/256
        duty = 0;   run(256);
        duty = 255; run(256);
        duty = 128; run(100); duty = 10; run(156);   // change mid-period must not take effect until wrap
        duty = 1;   run(512);
        // change duty exactly while cnt==255: the value present at that edge must be latched
        duty = 200; run(255); duty = 50;  run(257);
        duty = 7;   run(255); duty = 230; run(257);
        // mid-run reset
        rst_n = 0; run(2); rst_n = 1; run(300);
        for (i = 0; i < 6; i = i + 1) begin duty = $random(seed); run(256); end
        run(256);
        `CHECK("func", 1, 1'b1, (mis0 == 0 || mis1 == 0))
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
