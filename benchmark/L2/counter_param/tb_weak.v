// Weak testbench (Exp. 2 baseline): default parameters only; counts 10 enabled cycles and checks the value, then
// holds with en = 0. No wrap at MOD, no tc check, no second parameter set, no reset-priority or mid-run reset
// check, no per-cycle reference - see docs/testbench_protocol.md
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
module tb_counter_param;
    reg clk = 0, rst_n = 0, en = 0;
    wire [7:0] count;
    wire       tc;

    counter_param dut (.clk(clk), .rst_n(rst_n), .en(en), .count(count), .tc(tc));   // WIDTH = 8, MOD = 200
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED;

    initial begin
        rst_n = 0; en = 0;
        repeat (3) @(negedge clk);
        rst_n = 1; en = 1;
        repeat (10) @(negedge clk);
        `CHECK("func", 1, 8'd10, count)
        en = 0;
        repeat (3) @(negedge clk);
        `CHECK("func", 2, 8'd10, count)
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
