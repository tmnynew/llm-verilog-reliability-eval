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

module tb_barrel_shifter8;
    reg  [7:0] din;
    reg  [2:0] shamt;
    reg  [1:0] mode;
    wire [7:0] dout;

    barrel_shifter8 dut (.din(din), .shamt(shamt), .mode(mode), .dout(dout));

    integer n_checks = 0, n_fail = 0, i, k, s;
    reg [7:0] exp;

    initial begin
        for (i = 0; i < 8192; i = i + 1) begin
            {mode, shamt, din} = i[12:0];
            s = shamt;  // signed integer copy so that k - s may go negative
            // bit-by-bit behavioural reference
            for (k = 0; k < 8; k = k + 1) begin
                case (mode)
                    2'b00: exp[k] = (k - s >= 0) ? din[k - s] : 1'b0;
                    2'b01: exp[k] = (k + s <= 7) ? din[k + s] : 1'b0;
                    2'b10: exp[k] = (k + s <= 7) ? din[k + s] : din[7];
                    2'b11: exp[k] = din[(k - s + 8) % 8];
                endcase
            end
            #1;
            `CHECK("func", i, exp, dout)
        end
        if (n_fail == 0) $display("TB_RESULT PASS n_checks=%0d", n_checks);
        else             $display("TB_RESULT FAIL n_fail=%0d n_checks=%0d", n_fail, n_checks);
        $finish;
    end

    initial begin
        #1000000;
        $display("TB_FAIL tag=crash case=0 exp=0 got=0");
        $display("TB_RESULT FAIL n_fail=1 n_checks=%0d", n_checks);
        $finish;
    end
endmodule
`undef CHECK
