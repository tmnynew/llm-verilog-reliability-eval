// Weak testbench (Exp. 2 baseline): two well-formed frames at one comfortable device-clock speed; checks that a
// valid pulse appears and data matches. No parity/stop errors, no timeout/gap cases, no glitches, no pulse-width
// or valid/err exclusivity checks, no mid-frame reset - see docs/testbench_protocol.md
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
module tb_ps2_rx;
    localparam TO = 200;
    reg        clk = 0, rst_n = 0, ps2_clk = 1, ps2_data = 1;
    wire [7:0] data;
    wire       valid, err;

    ps2_rx #(.TIMEOUT(TO)) dut (.clk(clk), .rst_n(rst_n), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
                                .data(data), .valid(valid), .err(err));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, b;
    integer   valid_cnt = 0;
    reg [7:0] cap = 0;
    always @(negedge clk) if (valid === 1'b1) begin valid_cnt = valid_cnt + 1; cap = data; end

    task bit_out;
        input b;
        begin
            ps2_data = b;
            repeat (20) @(negedge clk);
            ps2_clk = 0;
            repeat (20) @(negedge clk);
            ps2_clk = 1;
        end
    endtask

    task frame;
        input [7:0] d;
        input integer id;
        reg [10:0] bits;
        begin
            bits = {1'b1, ~(^d), d, 1'b0};
            valid_cnt = 0;
            @(negedge clk);
            for (b = 0; b < 11; b = b + 1) bit_out(bits[b]);
            ps2_data = 1;
            repeat (10) @(negedge clk);
            `CHECK("proto", id * 10 + 1, 1, valid_cnt)
            `CHECK("func",  id * 10 + 2, d, cap)
        end
    endtask

    initial begin
        rst_n = 0; ps2_clk = 1; ps2_data = 1;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (6) @(negedge clk);
        frame(8'h1C, 1);
        frame(8'hA7, 2);
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
