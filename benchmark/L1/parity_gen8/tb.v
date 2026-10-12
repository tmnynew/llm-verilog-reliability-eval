// Exhaustive self-checking testbench 鈥?see docs/testbench_protocol.md
`timescale 1ns/1ps
`define CHECK(_t, _id, _e, _g) \
    begin \
        n_checks = n_checks + 1; \
        if ((_e) !== (_g)) begin \
            n_fail = n_fail + 1; \
            if (n_fail <= 20) $display("TB_FAIL tag=%s case=%0d exp=%0h got=%0h", _t, _id, _e, _g); \
        end \
    end

module tb_parity_gen8;
    reg  [7:0] data;
    reg        odd;
    wire       parity;

    parity_gen8 dut (.data(data), .odd(odd), .parity(parity));

    integer n_checks = 0, n_fail = 0, i, k, ones;
    reg exp;

    initial begin
        for (i = 0; i < 512; i = i + 1) begin
            {odd, data} = i[8:0];
            ones = 0;
            for (k = 0; k < 8; k = k + 1) ones = ones + data[k];
            exp = odd ? ~ones[0] : ones[0];
            #1;
            `CHECK("func", i, exp, parity)
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
