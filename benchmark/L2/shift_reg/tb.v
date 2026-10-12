// Cycle-level self-checking testbench with a 0..1 cycle latency window - see docs/testbench_protocol.md
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
`define WCHECK(_t, _id, _r, _rd, _g) \
    begin \
        n_checks = n_checks + 1; \
        if ((_g) !== (_r) && (_g) !== (_rd)) begin \
            n_fail = n_fail + 1; \
            if (n_fail <= 20) $display("TB_FAIL tag=%s case=%0d exp=%0h got=%0h", _t, _id, _r, _g); \
        end \
    end
module tb_shift_reg;
    reg        clk = 0, rst_n = 0, s_in = 0;
    reg  [1:0] mode = 0;
    reg  [7:0] d_in = 0;
    wire [7:0] q;
    wire       s_out;

    shift_reg dut (.clk(clk), .rst_n(rst_n), .mode(mode), .d_in(d_in), .s_in(s_in), .q(q), .s_out(s_out));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i, j;
    reg [7:0] rq = 0;
    always @(posedge clk) begin
        if (!rst_n) rq <= 0;
        else case (mode)
            2'b00: rq <= rq;
            2'b01: rq <= {rq[6:0], s_in};
            2'b10: rq <= {s_in, rq[7:1]};
            default: rq <= d_in;
        endcase
    end
    wire rs_out = (mode == 2'b01) ? rq[7] : (mode == 2'b10) ? rq[0] : 1'b0;

    task step;
        begin
            cyc = cyc + 1;
            if (!rst_n) `CHECK("reset", cyc, 8'd0, q)
            else begin
                `CHECK("func", cyc, rq, q)
                `CHECK("func", cyc + 100000, rs_out, s_out)
            end
            mode = $random(seed); d_in = $random(seed); s_in = $random(seed);
        end
    endtask

    task run;
        input integer n;
        begin for (j = 0; j < n; j = j + 1) begin @(negedge clk); step; end end
    endtask

    task fixed;   // hold a specific op for n cycles (data random)
        input [1:0] m; input integer n;
        begin for (j = 0; j < n; j = j + 1) begin @(negedge clk); step; mode = m; end end
    endtask

    initial begin
        mode = 2'b11; d_in = 8'hFF; run(3);       // load during reset must be ignored
        rst_n = 1;
        fixed(2'b11, 2); fixed(2'b01, 12); fixed(2'b10, 12); fixed(2'b00, 6);
        fixed(2'b11, 1); fixed(2'b10, 20);
        run(3000);
        rst_n = 0; run(2); rst_n = 1; run(500);
        mode = 0; run(2);
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
`undef WCHECK
