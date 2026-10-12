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

module tb_gray_conv4;
    reg  [3:0] din;
    reg        mode;
    wire [3:0] dout;

    gray_conv4 dut (.din(din), .mode(mode), .dout(dout));

    integer n_checks = 0, n_fail = 0, i;
    reg [3:0] exp, g;

    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            {mode, din} = i[4:0];
            if (!mode) exp = din ^ (din >> 1);
            else begin
                exp[3] = din[3]; exp[2] = exp[3] ^ din[2]; exp[1] = exp[2] ^ din[1]; exp[0] = exp[1] ^ din[0];
            end
            #1;
            `CHECK("func", i, exp, dout)
        end
        // round trip: bin -> gray -> bin must be identity
        for (i = 0; i < 16; i = i + 1) begin
            mode = 0; din = i[3:0]; #1; g = dout;
            mode = 1; din = g;      #1;
            `CHECK("func", 100 + i, i[3:0], dout)
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
