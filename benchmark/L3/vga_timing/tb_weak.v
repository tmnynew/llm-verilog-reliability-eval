// Weak testbench (Exp. 2 baseline): default 640x480 geometry only; counts de and hsync-low cycles over one full
// line (800 cycles) after reset and checks x reaches 639 and vsync is idle. No per-cycle reference, no
// vertical timing (no full frame), no small-geometry instance, no x/y = 0 outside de, no reset-value or
// mid-frame reset check
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
module tb_vga_timing;
    reg        clk = 0, rst_n = 0;
    wire       hsync, vsync, de;
    wire [9:0] x, y;
    vga_timing dut (.clk(clk), .rst_n(rst_n), .hsync(hsync), .vsync(vsync), .de(de), .x(x), .y(y));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i;
    integer de_cnt = 0, hs_low = 0, xmax = 0;

    initial begin
        rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        for (i = 0; i < 800; i = i + 1) begin
            @(negedge clk);
            if (de === 1'b1) begin de_cnt = de_cnt + 1; if (x > xmax) xmax = x; end
            if (hsync === 1'b0) hs_low = hs_low + 1;
        end
        `CHECK("func",   1, 640, de_cnt)
        `CHECK("timing", 2, 96, hs_low)
        `CHECK("func",   3, 639, xmax)
        `CHECK("func",   4, 1'b1, vsync)
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
