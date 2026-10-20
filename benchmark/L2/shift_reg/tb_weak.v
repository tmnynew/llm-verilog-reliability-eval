// Weak testbench (Exp. 2 baseline): one load, three left shifts, three right shifts and a hold, checking q only.
// No s_out check, no reset-value check, no load during reset, no random mode/data mix, no mid-run reset
//
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
module tb_shift_reg;
    reg        clk = 0, rst_n = 0, s_in = 0;
    reg  [1:0] mode = 0;
    reg  [7:0] d_in = 0;
    wire [7:0] q;
    wire       s_out;

    shift_reg dut (.clk(clk), .rst_n(rst_n), .mode(mode), .d_in(d_in), .s_in(s_in), .q(q), .s_out(s_out));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED;

    initial begin
        rst_n = 0; mode = 2'b00;
        repeat (3) @(negedge clk);
        rst_n = 1;
        mode = 2'b11; d_in = 8'h5A; @(negedge clk);
        `CHECK("func", 1, 8'h5A, q)
        mode = 2'b01; s_in = 1'b0; repeat (3) @(negedge clk);
        `CHECK("func", 2, 8'hD0, q)
        mode = 2'b10; s_in = 1'b1; repeat (3) @(negedge clk);
        `CHECK("func", 3, 8'hFA, q)
        mode = 2'b00; d_in = 8'h00; repeat (2) @(negedge clk);
        `CHECK("func", 4, 8'hFA, q)
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
