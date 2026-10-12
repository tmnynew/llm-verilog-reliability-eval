// Cycle-level self-checking testbench (latency window 0) 鈥?see docs/testbench_protocol.md
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

module tb_counter_param;
    reg clk = 0, rst_n = 0, en = 0;
    wire [7:0] count_a;  wire tc_a;   // default parameters  (WIDTH=8,  MOD=200)
    wire [4:0] count_b;  wire tc_b;   // overridden          (WIDTH=5,  MOD=20)

    counter_param                       dut_a (.clk(clk), .rst_n(rst_n), .en(en), .count(count_a), .tc(tc_a));
    counter_param #(.WIDTH(5), .MOD(20)) dut_b (.clk(clk), .rst_n(rst_n), .en(en), .count(count_b), .tc(tc_b));

    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED;
    integer ref_a = 0, ref_b = 0;
    reg in_reset_phase = 1;

    // behavioural reference (same edge as the DUT)
    always @(posedge clk) begin
        if (!rst_n) begin ref_a <= 0; ref_b <= 0; end
        else if (en) begin
            ref_a <= (ref_a == 199) ? 0 : ref_a + 1;
            ref_b <= (ref_b == 19)  ? 0 : ref_b + 1;
        end
    end

    task compare;
        begin
            if (in_reset_phase) begin
                `CHECK("reset", cyc, ref_a[7:0], count_a)
                `CHECK("reset", cyc, ref_b[4:0], count_b)
            end else begin
                `CHECK("func", cyc, ref_a[7:0], count_a)
                `CHECK("func", cyc, ref_b[4:0], count_b)
            end
            `CHECK("func", cyc, (en && ref_a == 199), tc_a)
            `CHECK("func", cyc, (en && ref_b == 19),  tc_b)
        end
    endtask

    integer i;
    initial begin
        // --- reset phase: 4 cycles, en toggling to prove reset has priority ---
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk); en = i[0]; rst_n = 0; cyc = cyc + 1;
        end
        @(negedge clk); compare;
        in_reset_phase = 0;
        rst_n = 1;

        // --- free-running with random enable: > 3 full periods of MOD=200 ---
        for (i = 0; i < 700; i = i + 1) begin
            @(negedge clk); cyc = cyc + 1;
            compare;
            en = ($random(seed) & 3) != 0;  // en high 75 % of cycles
        end

        // --- mid-run synchronous reset while count != 0 ---
        in_reset_phase = 1;
        @(negedge clk); cyc = cyc + 1; compare; rst_n = 0; en = 1;
        @(negedge clk); cyc = cyc + 1; compare;   // reset must have taken effect at this edge
        rst_n = 1;
        in_reset_phase = 0;
        for (i = 0; i < 50; i = i + 1) begin
            @(negedge clk); cyc = cyc + 1; compare; en = 1;
        end

        if (n_fail == 0) $display("TB_RESULT PASS n_checks=%0d", n_checks);
        else             $display("TB_RESULT FAIL n_fail=%0d n_checks=%0d", n_fail, n_checks);
        $finish;
    end

    initial begin
        #200000;
        $display("TB_FAIL tag=crash case=0 exp=0 got=0");
        $display("TB_RESULT FAIL n_fail=1 n_checks=%0d", n_checks);
        $finish;
    end
endmodule
`undef CHECK
