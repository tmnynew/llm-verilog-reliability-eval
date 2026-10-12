// Transaction-level testbench for the VGA timing generator: reference model with 0..1 cycle window, per-frame pulse statistics, default geometry instance - see docs/testbench_protocol.md
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
module tb_vga_timing;
    // small geometry instance checked cycle by cycle against a reference model
    localparam HA = 16, HF = 2, HS = 4, HB = 3, VA = 8, VF = 1, VS = 2, VB = 3;
    localparam HT = HA + HF + HS + HB, VT = VA + VF + VS + VB;   // 25 x 14 = 350 cycles / frame
    reg        clk = 0, rst_n = 0;
    wire       hsync, vsync, de;
    wire [9:0] x, y;
    vga_timing #(.H_ACTIVE(HA), .H_FP(HF), .H_SYNC(HS), .H_BP(HB), .V_ACTIVE(VA), .V_FP(VF), .V_SYNC(VS), .V_BP(VB))
        dut (.clk(clk), .rst_n(rst_n), .hsync(hsync), .vsync(vsync), .de(de), .x(x), .y(y));
    // default geometry instance: only counted over the first two lines
    wire       fhs, fvs, fde;
    wire [9:0] fx, fy;
    vga_timing dut_full (.clk(clk), .rst_n(rst_n), .hsync(fhs), .vsync(fvs), .de(fde), .x(fx), .y(fy));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, cyc = 0;

    // reference model with a one-cycle delayed copy
    reg [9:0] rh = 0, rv = 0;
    wire      r_hs = ~(rh >= HA + HF && rh < HA + HF + HS);
    wire      r_vs = ~(rv >= VA + VF && rv < VA + VF + VS);
    wire      r_de = (rh < HA) && (rv < VA);
    wire [9:0] r_x = r_de ? rh : 10'd0;
    wire [9:0] r_y = r_de ? rv : 10'd0;
    reg        d_hs = 1, d_vs = 1, d_de = 0;
    reg [9:0]  d_x = 0, d_y = 0;
    always @(posedge clk) begin
        if (!rst_n) begin rh <= 0; rv <= 0; d_hs <= 1; d_vs <= 1; d_de <= 0; d_x <= 0; d_y <= 0; end
        else begin
            if (rh == HT - 1) begin rh <= 0; rv <= (rv == VT - 1) ? 0 : rv + 1; end else rh <= rh + 1;
            d_hs <= r_hs; d_vs <= r_vs; d_de <= r_de; d_x <= r_x; d_y <= r_y;
        end
    end

    integer de_cnt = 0, hs_low = 0, hs_falls = 0, vs_low = 0, vs_falls = 0;
    reg     hs_p = 1, vs_p = 1;
    reg     m0, m1;
    task step;                                  // one cycle: consistency check + statistics
        begin
            @(negedge clk); cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 2'b11, {hsync, vsync})
            end else begin
                m0 = (hsync === r_hs && vsync === r_vs && de === r_de && x === r_x && y === r_y);
                m1 = (hsync === d_hs && vsync === d_vs && de === d_de && x === d_x && y === d_y);
                n_checks = n_checks + 1;
                if (!m0 && !m1) begin
                    n_fail = n_fail + 1;
                    if (n_fail <= 20) $display("TB_FAIL tag=func case=%0d exp=%0h got=%0h", cyc, {r_hs, r_vs, r_de, r_x, r_y}, {hsync, vsync, de, x, y});
                end
                if (de === 1'b1) de_cnt = de_cnt + 1;
                if (hsync === 1'b0) hs_low = hs_low + 1;
                if (vsync === 1'b0) vs_low = vs_low + 1;
                if (hs_p === 1'b1 && hsync === 1'b0) hs_falls = hs_falls + 1;
                if (vs_p === 1'b1 && vsync === 1'b0) vs_falls = vs_falls + 1;
            end
            hs_p = hsync; vs_p = vsync;
        end
    endtask

    task within1;                                // |exp - got| <= 1
        input [31:0] tag_id;
        input integer e, g;
        begin
            n_checks = n_checks + 1;
            if (g < e - 1 || g > e + 1) begin
                n_fail = n_fail + 1;
                if (n_fail <= 20) $display("TB_FAIL tag=timing case=%0d exp=%0d got=%0d", tag_id, e, g);
            end
        end
    endtask

    // default-geometry statistics over the first 1650 cycles after reset release
    integer f_de = 0, f_hs_low = 0, f_vs_low = 0, f_xmax = 0, f_ymax = 0, f_hs_falls = 0, f_win = 0;
    reg     fhs_p = 1;
    always @(negedge clk) if (rst_n && f_win > 0) begin
        f_win = f_win - 1;
        if (fde === 1'b1) begin f_de = f_de + 1; if (fx > f_xmax) f_xmax = fx; if (fy > f_ymax) f_ymax = fy; end
        if (fhs === 1'b0) f_hs_low = f_hs_low + 1;
        if (fvs === 1'b0) f_vs_low = f_vs_low + 1;
        if (fhs_p === 1'b1 && fhs === 1'b0) f_hs_falls = f_hs_falls + 1;
        fhs_p = fhs;
    end

    integer NF;
    initial begin
        rst_n = 0;
        step; step; step;
        rst_n = 1; f_win = 1650;
        // 6 full frames of the small geometry
        NF = 6;
        de_cnt = 0; hs_low = 0; hs_falls = 0; vs_low = 0; vs_falls = 0;
        for (i = 0; i < NF * HT * VT; i = i + 1) step;
        within1(100, NF * HA * VA, de_cnt);
        within1(101, NF * VT * HS, hs_low);
        within1(102, NF * VT, hs_falls);
        within1(103, NF * VS * HT, vs_low);
        within1(104, NF, vs_falls);
        // reset in the middle of a frame, then run 2 more frames
        for (i = 0; i < 137; i = i + 1) step;
        rst_n = 0; step; step;
        rst_n = 1;
        NF = 2;
        de_cnt = 0; hs_low = 0; hs_falls = 0; vs_low = 0; vs_falls = 0;
        for (i = 0; i < NF * HT * VT; i = i + 1) step;
        within1(110, NF * HA * VA, de_cnt);
        within1(111, NF * VT * HS, hs_low);
        within1(112, NF * VT, hs_falls);
        within1(113, NF * VS * HT, vs_low);
        within1(114, NF, vs_falls);
        // default geometry: two full lines plus 50 pixels of the third
        `CHECK("proto", 200, 0, f_win)
        within1(201, 2 * 640 + 50, f_de);
        within1(202, 2 * 96, f_hs_low);
        `CHECK("proto", 203, 2, f_hs_falls)
        `CHECK("proto", 204, 0, f_vs_low)
        `CHECK("func", 205, 639, f_xmax)
        `CHECK("func", 206, 2, f_ymax)
        if (n_fail == 0) $display("TB_RESULT PASS n_checks=%0d", n_checks);
        else             $display("TB_RESULT FAIL n_fail=%0d n_checks=%0d", n_fail, n_checks);
        $finish;
    end

    initial begin
        #2000000;
        $display("TB_FAIL tag=crash case=0 exp=0 got=0");
        $display("TB_RESULT FAIL n_fail=1 n_checks=%0d", n_checks);
        $finish;
    end
endmodule
`undef CHECK
