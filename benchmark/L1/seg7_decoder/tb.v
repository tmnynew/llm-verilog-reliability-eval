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

module tb_seg7_decoder;
    reg  [3:0] hex;
    wire [6:0] seg;

    seg7_decoder dut (.hex(hex), .seg(seg));

    integer n_checks = 0, n_fail = 0, i;
    reg [6:0] table_ [0:15];

    initial begin
        table_[0]  = 7'b100_0000; table_[1]  = 7'b111_1001; table_[2]  = 7'b010_0100; table_[3]  = 7'b011_0000;
        table_[4]  = 7'b001_1001; table_[5]  = 7'b001_0010; table_[6]  = 7'b000_0010; table_[7]  = 7'b111_1000;
        table_[8]  = 7'b000_0000; table_[9]  = 7'b001_0000; table_[10] = 7'b000_1000; table_[11] = 7'b000_0011;
        table_[12] = 7'b100_0110; table_[13] = 7'b010_0001; table_[14] = 7'b000_0110; table_[15] = 7'b000_1110;
        for (i = 0; i < 16; i = i + 1) begin
            hex = i[3:0];
            #1;
            `CHECK("func", i, table_[i], seg)
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
