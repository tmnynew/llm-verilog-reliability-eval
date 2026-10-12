// Weak testbench (Exp. 2 baseline): rising-edge mode only; three slow 0->1->0 transitions, then compares the
// pulse count and cnt. No falling/both/disabled modes, no per-cycle reference, no pulse alignment check,
// no reset-value check, no counter wrap, no mid-run reset, no random traffic - see docs/testbench_protocol.md
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
module tb_edge_detect;
    reg        clk = 0, rst_n = 0, sig = 0;
    reg  [1:0] mode = 2'b01;
    wire       pulse;
    wire [7:0] cnt;

    edge_detect dut (.clk(clk), .rst_n(rst_n), .sig(sig), .mode(mode), .pulse(pulse), .cnt(cnt));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, j, pulses = 0;

    task run;
        input integer n;
        begin
            for (j = 0; j < n; j = j + 1) begin
                @(negedge clk);
                if (pulse === 1'b1) pulses = pulses + 1;
            end
        end
    endtask

    initial begin
        rst_n = 0; sig = 0; mode = 2'b01;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);
        for (i = 0; i < 3; i = i + 1) begin
            sig = 1; run(4);
            sig = 0; run(4);
        end
        `CHECK("func", 1, 3, pulses)
        `CHECK("func", 2, 8'd3, cnt)
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
