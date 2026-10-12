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

module tb_lzc8;
    reg  [7:0] din;
    wire [3:0] count;
    wire       zero;

    lzc8 dut (.din(din), .count(count), .zero(zero));

    integer n_checks = 0, n_fail = 0, i, k, exp;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            din = i[7:0];
            exp = 8;
            for (k = 7; k >= 0; k = k - 1)
                if (din[k] && exp == 8) exp = 7 - k;
            #1;
            `CHECK("func", i, exp[3:0], count)
            `CHECK("func", i, (din == 0), zero)
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
