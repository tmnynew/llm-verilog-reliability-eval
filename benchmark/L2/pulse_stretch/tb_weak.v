// Weak testbench (Exp. 2 baseline): default LEN only; one single-cycle input pulse, checks that out is high
// shortly afterwards and low again later. No exact pulse-length check, no retrigger, no long input, no
// second LEN, no reset-value check, no input during reset, no mid-run reset, no random traffic
// - see docs/testbench_protocol.md
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
module tb_pulse_stretch;
    reg  clk = 0, rst_n = 0, in = 0;
    wire out;

    pulse_stretch dut (.clk(clk), .rst_n(rst_n), .in(in), .out(out));   // LEN = 8
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED;

    initial begin
        rst_n = 0; in = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (20) @(negedge clk);
        in = 1; @(negedge clk); in = 0;
        @(negedge clk);
        `CHECK("func", 1, 1'b1, out)              // stretched pulse has started
        repeat (18) @(negedge clk);
        `CHECK("func", 2, 1'b0, out)              // ... and ended well before 20 cycles
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
