// Weak testbench (Exp. 2 baseline): one write transaction to an acknowledging slave model; checks done,
// ack_err = 0 and the address/data byte received by the slave. No read transaction, no NACK cases, no
// SCL-period or START/STOP monitor, no start while busy, no reset-value or mid-transaction reset check
// - see docs/testbench_protocol.md
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
module tb_i2c_master;
    localparam DIV = 4;
    localparam [6:0] SLV = 7'h50;
    reg        clk = 0, rst_n = 0, start = 0, rw = 0;
    reg  [6:0] addr = 0;
    reg  [7:0] wdata = 0;
    wire [7:0] rdata;
    wire       busy, done, ack_err, scl_o, sda_o;
    reg        sda_slv = 1;
    wire       sda_i = sda_o & sda_slv;         // wired-AND bus
    wire       scl   = scl_o;

    i2c_master #(.CLK_DIV(DIV)) dut (.clk(clk), .rst_n(rst_n), .start(start), .rw(rw), .addr(addr), .wdata(wdata),
                                     .rdata(rdata), .busy(busy), .done(done), .ack_err(ack_err),
                                     .scl_o(scl_o), .sda_o(sda_o), .sda_i(sda_i));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, t, done_cnt = 0;
    always @(negedge clk) if (done === 1'b1) done_cnt = done_cnt + 1;

    // minimal slave model: ACKs address SLV and one data byte (clocked at negedge clk, edge-detected, race-free)
    reg [7:0] s_sh = 0, s_addr_byte = 0, slv_mem = 0;
    integer   s_state = 0, s_bit = 0;
    reg       scl_q = 1, sda_q = 1;
    always @(negedge clk) begin
        if (rst_n) begin
            if (scl === 1'b1 && sda_q === 1'b1 && sda_i === 1'b0) begin s_state = 1; s_bit = 0; sda_slv = 1; end   // START
            if (scl === 1'b1 && sda_q === 1'b0 && sda_i === 1'b1) begin s_state = 0; sda_slv = 1; end            // STOP
            if (scl_q === 1'b0 && scl === 1'b1 && (s_state == 1 || s_state == 3)) begin s_sh = {s_sh[6:0], sda_i}; s_bit = s_bit + 1; end
            if (scl_q === 1'b1 && scl === 1'b0) case (s_state)
                1: if (s_bit == 8) begin
                       s_addr_byte = s_sh;
                       if (s_sh[7:1] == SLV) begin sda_slv = 0; s_state = 2; end else s_state = 9;
                   end
                2: begin sda_slv = 1; s_bit = 0; s_state = 3; end
                3: if (s_bit == 8) begin slv_mem = s_sh; sda_slv = 0; s_state = 4; end
                4: begin sda_slv = 1; s_state = 9; end
                default: ;
            endcase
        end
        scl_q = scl; sda_q = sda_i;
    end

    initial begin
        rst_n = 0; start = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);

        rw = 0; addr = SLV; wdata = 8'hA5; start = 1; done_cnt = 0;
        @(negedge clk); start = 0;
        `CHECK("proto", 1, 1'b1, busy)
        t = 0;
        while (busy === 1'b1 && t < 100 * DIV) begin @(negedge clk); t = t + 1; end
        `CHECK("timing", 2, 1'b0, busy)
        repeat (2) @(negedge clk);
        `CHECK("proto", 3, 1, done_cnt)
        `CHECK("func",  4, 1'b0, ack_err)
        `CHECK("func",  5, {SLV, 1'b0}, s_addr_byte)
        `CHECK("func",  6, 8'hA5, slv_mem)
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
