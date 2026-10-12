// Exhaustive self-checking testbench - see docs/testbench_protocol.md
`timescale 1ns/1ps
`define CHECK(_t, _id, _e, _g) \
    begin \
        n_checks = n_checks + 1; \
        if ((_e) !== (_g)) begin \
            n_fail = n_fail + 1; \
            if (n_fail <= 20) $display("TB_FAIL tag=%s case=%0d exp=%0h got=%0h", _t, _id, _e, _g); \
        end \
    end

module tb_cla_adder4;
    reg  [3:0] a, b;
    reg        cin;
    wire [3:0] sum;
    wire       cout, p_out, g_out;

    cla_adder4 dut (.a(a), .b(b), .cin(cin), .sum(sum), .cout(cout), .p_out(p_out), .g_out(g_out));

    integer n_checks = 0, n_fail = 0, i;
    reg [4:0] exp_sum, exp_g;

    initial begin
        for (i = 0; i < 512; i = i + 1) begin
            {cin, a, b} = i[8:0];
            exp_sum = a + b + cin;
            exp_g   = a + b;
            #1;
            `CHECK("func", i, exp_sum[3:0], sum)
            `CHECK("func", i, exp_sum[4], cout)
            `CHECK("func", i, &(a ^ b), p_out)
            `CHECK("func", i, exp_g[4], g_out)
        end
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
