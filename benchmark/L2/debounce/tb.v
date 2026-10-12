// Cycle-level self-checking testbench with a 0..1 cycle latency window – see docs/testbench_protocol.md
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

module tb_debounce;
    reg  clk = 0, rst_n = 0, btn_in = 0;
    wire out_a, out_b;

    debounce                      dut_a (.clk(clk), .rst_n(rst_n), .btn_in(btn_in), .btn_out(out_a)); // STABLE_CYCLES = 16
    debounce #(.STABLE_CYCLES(3)) dut_b (.clk(clk), .rst_n(rst_n), .btn_in(btn_in), .btn_out(out_b));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i, j;
    // Latency-window consistency: the per-cycle check accepts either the zero-latency or the
    // one-cycle-delayed reference, so additionally each output must agree with *one* of the two
    // references over the whole run (mis_*0 == 0 or mis_*1 == 0).  This replaces aggregate toggle
    // counts, which legitimately differ by one for a registered output around a reset.
    integer mis_a0 = 0, mis_a1 = 0, mis_b0 = 0, mis_b1 = 0;

    // ---- behavioural references ----
    reg ref_a = 0, ref_b = 0, ref_a_d = 0, ref_b_d = 0;
    integer cnt_a = 0, cnt_b = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            ref_a <= 0; ref_b <= 0; cnt_a <= 0; cnt_b <= 0; ref_a_d <= 0; ref_b_d <= 0;
        end else begin
            ref_a_d <= ref_a; ref_b_d <= ref_b;
            if (btn_in == ref_a) cnt_a <= 0;
            else if (cnt_a == 15) begin ref_a <= btn_in; cnt_a <= 0; end
            else cnt_a <= cnt_a + 1;
            if (btn_in == ref_b) cnt_b <= 0;
            else if (cnt_b == 2) begin ref_b <= btn_in; cnt_b <= 0; end
            else cnt_b <= cnt_b + 1;
        end
    end

    task step;
        begin
            cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 1'b0, out_a)
                `CHECK("reset", cyc, 1'b0, out_b)
            end else begin
                if (out_a !== ref_a && out_a !== ref_a_d) begin
                    n_checks = n_checks + 1; n_fail = n_fail + 1;
                    if (n_fail <= 20) $display("TB_FAIL tag=func case=%0d exp=%0h got=%0h", cyc, ref_a, out_a);
                end else n_checks = n_checks + 1;
                if (out_b !== ref_b && out_b !== ref_b_d) begin
                    n_checks = n_checks + 1; n_fail = n_fail + 1;
                    if (n_fail <= 20) $display("TB_FAIL tag=func case=%0d exp=%0h got=%0h", cyc + 100000, ref_b, out_b);
                end else n_checks = n_checks + 1;
                if (out_a !== ref_a)   mis_a0 = mis_a0 + 1;
                if (out_a !== ref_a_d) mis_a1 = mis_a1 + 1;
                if (out_b !== ref_b)   mis_b0 = mis_b0 + 1;
                if (out_b !== ref_b_d) mis_b1 = mis_b1 + 1;
            end
        end
    endtask

    task feed;
        input b;
        begin
            btn_in = b;
            @(negedge clk);
            step;
        end
    endtask

    task bouncy_press;      // noisy transition to `level`, then hold
        input level;
        input integer noise_cycles, hold_cycles;
        begin
            for (j = 0; j < noise_cycles; j = j + 1) feed($random(seed));
            for (j = 0; j < hold_cycles; j = j + 1)  feed(level);
        end
    endtask

    initial begin
        rst_n = 0;
        for (i = 0; i < 3; i = i + 1) feed(1);   // input high during reset must not leak
        rst_n = 1;
        // glitches shorter than STABLE_CYCLES: 15 cycles high (dut_a must ignore, dut_b must accept)
        for (i = 0; i < 15; i = i + 1) feed(1);
        for (i = 0; i < 20; i = i + 1) feed(0);
        // exactly 16 cycles high → dut_a toggles on the 16th edge
        for (i = 0; i < 16; i = i + 1) feed(1);
        for (i = 0; i < 20; i = i + 1) feed(1);
        // bouncy release / press sequences
        bouncy_press(0, 25, 40);
        bouncy_press(1, 25, 40);
        bouncy_press(0, 10, 40);
        // 2-cycle glitches for dut_b (STABLE_CYCLES=3)
        for (i = 0; i < 10; i = i + 1) begin feed(1); feed(1); feed(0); feed(0); feed(0); end
        // mid-run reset while output is high
        bouncy_press(1, 5, 30);
        rst_n = 0; feed(1); feed(1);
        rst_n = 1;
        for (i = 0; i < 40; i = i + 1) feed(1);
        // random
        for (i = 0; i < 2000; i = i + 1) feed(($random(seed) & 7) != 0 ? btn_in : ~btn_in);  // 1/8 toggle probability
        feed(0); feed(0);

        `CHECK("func", 1, 1'b1, (mis_a0 == 0 || mis_a1 == 0))
        `CHECK("func", 2, 1'b1, (mis_b0 == 0 || mis_b1 == 0))
        if (n_fail == 0) $display("TB_RESULT PASS n_checks=%0d", n_checks);
        else             $display("TB_RESULT FAIL n_fail=%0d n_checks=%0d", n_fail, n_checks);
        $finish;
    end

    initial begin
        #500000;
        $display("TB_FAIL tag=crash case=0 exp=0 got=0");
        $display("TB_RESULT FAIL n_fail=1 n_checks=%0d", n_checks);
        $finish;
    end
endmodule
`undef CHECK
