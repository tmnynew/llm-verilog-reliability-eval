// Exhaustive-control self-checking testbench (all sel/en combinations x data patterns)
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

module tb_mux8_1;
    reg  [31:0] din4;
    reg  [15:0] din2;
    reg  [2:0]  sel;
    reg         en;
    wire [3:0]  dout4;
    wire [1:0]  dout2;

    mux8_1            dut_a (.din(din4), .sel(sel), .en(en), .dout(dout4)); // WIDTH = 4 (default)
    mux8_1 #(.WIDTH(2)) dut_b (.din(din2), .sel(sel), .en(en), .dout(dout2));

    integer n_checks = 0, n_fail = 0, i, k, seed = `SEED;
    reg [3:0] exp4;
    reg [1:0] exp2;

    initial begin
        // pattern 0: channel index as data; patterns 1..3: one-hot channels; 4..: random
        for (k = 0; k < 40; k = k + 1) begin
            if (k == 0)       begin din4 = 32'h7654_3210; din2 = 16'hE4E4; end
            else if (k <= 8)  begin din4 = 32'hF << (4 * (k - 1)); din2 = 16'h3 << (2 * (k - 1)); end
            else if (k == 9)  begin din4 = 32'hFFFF_FFFF; din2 = 16'hFFFF; end
            else              begin din4 = $random(seed); din2 = $random(seed); end
            for (i = 0; i < 16; i = i + 1) begin
                {en, sel} = i[3:0];
                exp4 = en ? din4[sel*4 +: 4] : 4'd0;
                exp2 = en ? din2[sel*2 +: 2] : 2'd0;
                #1;
                `CHECK("func", k * 16 + i, exp4, dout4)
                `CHECK("func", 10000 + k * 16 + i, exp2, dout2)
            end
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
