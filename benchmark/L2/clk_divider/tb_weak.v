// Weak testbench (Exp. 2 baseline): div fixed at 4, counts tick pulses and clk_out rising edges over a window.
// No per-cycle reference, no reset-value checks, no div = 2/3/255, no div change at run time, no duty-cycle
// check, no mid-run reset
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
module tb_clk_divider;
    reg        clk = 0, rst_n = 0;
    reg  [7:0] div = 8'd4;
    wire       tick, clk_out;

    clk_divider dut (.clk(clk), .rst_n(rst_n), .div(div), .tick(tick), .clk_out(clk_out));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i;
    integer ticks = 0, rises = 0;
    reg     co_p = 0;

    initial begin
        rst_n = 0; div = 4;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (8) @(negedge clk);                 // settle
        co_p = clk_out;
        for (i = 0; i < 40; i = i + 1) begin
            @(negedge clk);
            if (tick === 1'b1) ticks = ticks + 1;
            if (co_p === 1'b0 && clk_out === 1'b1) rises = rises + 1;
            co_p = clk_out;
        end
        `CHECK("func",   1, 10, ticks)             // 40 cycles / 4
        `CHECK("func",   2, 10, rises)
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
