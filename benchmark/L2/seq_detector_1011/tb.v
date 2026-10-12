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

module tb_seq_detector_1011;
    reg  clk = 0, rst_n = 0, din = 0;
    wire det;

    seq_detector_1011 dut (.clk(clk), .rst_n(rst_n), .din(din), .det(det));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i;
    integer ref_pulses = 0, dut_pulses = 0;

    // ---- behavioural reference: 4-bit history, registered detect ----
    reg [3:0] hist = 0;
    reg ref_det = 0, ref_det_d = 0, det_prev = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            hist <= 4'b0000; ref_det <= 0; ref_det_d <= 0;
        end else begin
            hist      <= {hist[2:0], din};
            ref_det   <= ({hist[2:0], din} == 4'b1011);
            ref_det_d <= ref_det;
        end
    end

    // Window check every cycle: DUT may be aligned with ref_det (0 latency) or ref_det_d (1 latency).
    task step;   // called at negedge, after outputs settled
        begin
            cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 1'b0, det)
            end else begin
                if (det !== ref_det && det !== ref_det_d) begin
                    n_checks = n_checks + 1; n_fail = n_fail + 1;
                    if (n_fail <= 20) $display("TB_FAIL tag=state case=%0d exp=%0h got=%0h", cyc, ref_det, det);
                end else n_checks = n_checks + 1;
                if (det === 1'b1 && det_prev === 1'b1) begin   // pulse wider than one cycle
                    n_checks = n_checks + 1; n_fail = n_fail + 1;
                    if (n_fail <= 20) $display("TB_FAIL tag=timing case=%0d exp=1 got=2", cyc);
                end
            end
            if (det === 1'b1) dut_pulses = dut_pulses + 1;
            if (ref_det)      ref_pulses = ref_pulses + 1;
            det_prev = det;
        end
    endtask

    task feed;  // drive one bit, then observe
        input b;
        begin
            din = b;
            @(negedge clk);
            step;
        end
    endtask

    reg [31:0] pattern;
    initial begin
        // reset for 3 cycles with a "101" prefix that must NOT survive the reset
        rst_n = 0;
        feed(1); feed(0); feed(1);
        rst_n = 1;
        feed(1); feed(0); feed(0);     // completes 1011 across the reset boundary only if history leaked
        // deterministic overlapping patterns
        pattern = 32'b1011011_10111011_1011_1011_0000_0000;
        for (i = 31; i >= 0; i = i - 1) feed(pattern[i]);
        // random stream, P(1) = 0.6
        for (i = 0; i < 3000; i = i + 1) feed(($random(seed) % 10 + 10) % 10 < 6);
        // mid-run reset immediately after a "101" prefix
        feed(1); feed(0); feed(1);
        rst_n = 0; feed(1); feed(1);
        rst_n = 1; feed(1); feed(0); feed(0); feed(0);
        for (i = 0; i < 500; i = i + 1) feed(($random(seed) % 10 + 10) % 10 < 6);
        // drain: two idle cycles so a 1-cycle-late pulse is still counted
        feed(0); feed(0);

        `CHECK("state", 0, ref_pulses, dut_pulses)
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
