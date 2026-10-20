// Weak testbench (Exp. 2 baseline): default TIMEOUT only; lets the timer expire without kicks, then kicks once
// and checks the flag is cleared. No exact-cycle timeout check, no regular-feeding case, no enable = 0 case,
// no second TIMEOUT, no reset-value check, no mid-run reset, no random traffic
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
module tb_watchdog;
    reg  clk = 0, rst_n = 0, enable = 0, kick = 0;
    wire timeout;

    watchdog dut (.clk(clk), .rst_n(rst_n), .enable(enable), .kick(kick), .timeout(timeout));   // TIMEOUT = 64
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED;

    initial begin
        rst_n = 0; enable = 1; kick = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (80) @(negedge clk);
        `CHECK("func", 1, 1'b1, timeout)          // expired without kicks
        kick = 1; @(negedge clk); kick = 0;
        `CHECK("func", 2, 1'b0, timeout)          // kick clears the flag
        if (n_fail == 0) $display("TB_RESULT PASS n_checks=%0d", n_checks);
        else             $display("TB_RESULT FAIL n_fail=%0d n_checks=%0d", n_fail, n_checks);
        $finish;
    end

    initial begin
        #100000;
        $display("TB_FAIL tag=crash case=0 exp=0 got=0");
        $display("TB_RESULT FAIL n_fail=1 n_checks=%0d", n_checks);
        $finish;
    end
endmodule
`undef CHECK
