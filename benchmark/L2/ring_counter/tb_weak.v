// Weak testbench (Exp. 2 baseline): left rotation only with en held high; checks the q sequence for two turns and
// the total number of wrap pulses. No right rotation, no en = 0 hold, no reset-value checks, no direction
// reversal, no mid-run reset, no random traffic - see docs/testbench_protocol.md
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
module tb_ring_counter;
    reg  clk = 0, rst_n = 0, en = 0, dir = 0;
    wire [3:0] q;
    wire       wrap;

    ring_counter dut (.clk(clk), .rst_n(rst_n), .en(en), .dir(dir), .q(q), .wrap(wrap));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, wraps = 0;
    reg [3:0] exp_q;

    initial begin
        rst_n = 0; en = 0; dir = 0;
        repeat (3) @(negedge clk);
        rst_n = 1; en = 1;
        exp_q = 4'b0001;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            exp_q = {exp_q[2:0], exp_q[3]};
            `CHECK("state", i, exp_q, q)
            if (wrap === 1'b1) wraps = wraps + 1;
        end
        `CHECK("func", 100, 2, wraps)
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
