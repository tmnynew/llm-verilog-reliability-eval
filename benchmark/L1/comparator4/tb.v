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

module tb_comparator4;
    reg  [3:0] a, b;
    reg        signed_mode;
    wire       gt, eq, lt;

    comparator4 dut (.a(a), .b(b), .signed_mode(signed_mode), .gt(gt), .eq(eq), .lt(lt));

    integer n_checks = 0, n_fail = 0, i;
    integer va, vb;

    initial begin
        for (i = 0; i < 512; i = i + 1) begin
            {signed_mode, a, b} = i[8:0];
            if (signed_mode) begin
                va = a[3] ? a - 16 : a;
                vb = b[3] ? b - 16 : b;
            end else begin
                va = a;
                vb = b;
            end
            #1;
            `CHECK("func", i, (va > vb), gt)
            `CHECK("func", i, (va == vb), eq)
            `CHECK("func", i, (va < vb), lt)
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
