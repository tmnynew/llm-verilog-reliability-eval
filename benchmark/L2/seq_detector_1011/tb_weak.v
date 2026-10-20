// Weak testbench (Exp. 2 baseline): two isolated "1011" patterns separated by zeros; counts cycles with det = 1
// after reset and expects exactly 2. No overlapping patterns, no per-cycle reference, no pulse alignment check,
// no reset-value check, no history-across-reset case, no random stream
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
module tb_seq_detector_1011;
    reg  clk = 0, rst_n = 0, din = 0;
    wire det;

    seq_detector_1011 dut (.clk(clk), .rst_n(rst_n), .din(din), .det(det));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, pulses = 0;
    reg [15:0] pattern = 16'b0000_1011_0000_1011;

    initial begin
        rst_n = 0; din = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        for (i = 15; i >= 0; i = i - 1) begin
            din = pattern[i];
            @(negedge clk);
            if (det === 1'b1) pulses = pulses + 1;
        end
        din = 0;
        for (i = 0; i < 3; i = i + 1) begin
            @(negedge clk);
            if (det === 1'b1) pulses = pulses + 1;
        end
        `CHECK("func", 1, 2, pulses)
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
