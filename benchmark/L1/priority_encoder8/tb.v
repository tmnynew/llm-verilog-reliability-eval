// Exhaustive self-checking testbench
`timescale 1ns/1ps
`define CHECK(_t, _id, _e, _g) \
    begin \
        n_checks = n_checks + 1; \
        if ((_e) !== (_g)) begin \
            n_fail = n_fail + 1; \
            if (n_fail <= 20) $display("TB_FAIL tag=%s case=%0d exp=%0h got=%0h", _t, _id, _e, _g); \
        end \
    end

module tb_priority_encoder8;
    reg  [7:0] in;
    wire [2:0] idx;
    wire       valid;

    priority_encoder8 dut (.in(in), .idx(idx), .valid(valid));

    integer n_checks = 0, n_fail = 0, i, k;
    reg [2:0] exp_idx;
    reg       exp_valid;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            in = i[7:0];
            exp_valid = (i != 0);
            exp_idx = 0;
            for (k = 0; k < 8; k = k + 1)
                if (in[k]) exp_idx = k[2:0];
            #1;
            `CHECK("func", i, exp_idx, idx)
            `CHECK("func", i, exp_valid, valid)
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
