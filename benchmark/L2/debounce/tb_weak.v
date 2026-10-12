// Weak testbench (Exp. 2 baseline): default instance only; one clean press and one clean release held well beyond
// STABLE_CYCLES, plus a check that the output has not moved 5 cycles into the press. No bouncy input, no
// glitch shorter than STABLE_CYCLES, no exact-16 boundary, no second parameter value, no reset-value check,
// no mid-run reset - see docs/testbench_protocol.md
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
module tb_debounce;
    reg  clk = 0, rst_n = 0, btn_in = 0;
    wire btn_out;

    debounce dut (.clk(clk), .rst_n(rst_n), .btn_in(btn_in), .btn_out(btn_out));   // STABLE_CYCLES = 16
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED;

    initial begin
        rst_n = 0; btn_in = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (20) @(negedge clk);
        btn_in = 1;
        repeat (5) @(negedge clk);
        `CHECK("func", 1, 1'b0, btn_out)          // not yet stable
        repeat (25) @(negedge clk);
        `CHECK("func", 2, 1'b1, btn_out)          // pressed
        btn_in = 0;
        repeat (5) @(negedge clk);
        `CHECK("func", 3, 1'b1, btn_out)
        repeat (25) @(negedge clk);
        `CHECK("func", 4, 1'b0, btn_out)          // released
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
