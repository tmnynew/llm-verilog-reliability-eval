// Weak testbench (Exp. 2 baseline): one duty value (128); waits one period for the latch, then counts high
// cycles over the next period. No per-cycle reference, no duty = 0/255/1, no mid-period duty change, no latch
// timing check, no reset-value check, no mid-run reset
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
module tb_pwm_gen;
    reg        clk = 0, rst_n = 0;
    reg  [7:0] duty = 0;
    wire       pwm;

    pwm_gen dut (.clk(clk), .rst_n(rst_n), .duty(duty), .pwm(pwm));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, high = 0;

    initial begin
        rst_n = 0; duty = 8'd128;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (256) @(negedge clk);              // first period: duty gets latched at the wrap
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            if (pwm === 1'b1) high = high + 1;
        end
        `CHECK("func", 1, 128, high)
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
