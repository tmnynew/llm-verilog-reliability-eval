// Transaction-level testbench for the PS/2 receiver: device model with variable clock, parity/stop errors, timeout and glitches
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

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, cyc = 0;
    always @(negedge clk) cyc = cyc + 1;

    integer   valid_cnt = 0, err_cnt = 0, valid_t = -1, err_t = -1, both = 0, wide = 0, t_last = -1;
    reg [7:0] cap = 0;
    reg       valid_p = 0, err_p = 0;
    always @(negedge clk) begin
        if (valid === 1'b1 && err === 1'b1) both = both + 1;
        if (valid === 1'b1) begin
            if (valid_p === 1'b1) wide = wide + 1; else begin valid_cnt = valid_cnt + 1; valid_t = cyc; cap = data; end
        end
        if (err === 1'b1) begin
            if (err_p === 1'b1) wide = wide + 1; else begin err_cnt = err_cnt + 1; err_t = cyc; end
        end
        valid_p = valid; err_p = err;
    end

    // device model: one bit = data set while clk high, then clk low for hp, then high for hp
    task bit_out;
        input b;
        input integer hp;
        begin
            ps2_data = b;
            repeat (hp) @(negedge clk);
            ps2_clk = 0; t_last = cyc;
            repeat (hp) @(negedge clk);
            ps2_clk = 1;
        end
    endtask

    task frame;
        input [7:0] d;
        input parity_ok, stop_ok;
        input integer hp;
        input integer gap_after, gap_len;       // insert an idle gap (clk high) after bit index gap_after (0 = none)
        input integer id;
        input integer expect_valid;            // 1: valid, 0: err, 2: nothing (frame silently dropped)
        integer b;
        reg [10:0] bits;
        reg p;
        begin
            p = ~(^d);
            if (!parity_ok) p = ~p;
            bits = {(stop_ok ? 1'b1 : 1'b0), p, d, 1'b0};
            valid_cnt = 0; err_cnt = 0;
            @(negedge clk);
            for (b = 0; b < 11; b = b + 1) begin
                bit_out(bits[b], hp);
                if (gap_after != 0 && b == gap_after) begin ps2_data = 1; repeat (gap_len) @(negedge clk); end
            end
            ps2_data = 1;
            repeat (10) @(negedge clk);
            if (expect_valid == 2) begin
                `CHECK("proto", id * 10 + 8, 0, valid_cnt)
                `CHECK("proto", id * 10 + 9, 0, err_cnt)
                repeat (TO + 10) @(negedge clk);   // let the receiver drop whatever it started on the tail bits
            end else if (expect_valid == 1) begin
                `CHECK("proto", id * 10 + 1, 1, valid_cnt)
                `CHECK("proto", id * 10 + 2, 0, err_cnt)
                `CHECK("func",  id * 10 + 3, d, cap)
                if (valid_cnt == 1) begin
                    n_checks = n_checks + 1;
                    if (valid_t - t_last < 1 || valid_t - t_last > 6) begin
                        n_fail = n_fail + 1;
                        if (n_fail <= 20) $display("TB_FAIL tag=timing case=%0d exp=%0d got=%0d", id * 10 + 4, t_last + 3, valid_t);
                    end
                end
            end else begin
                `CHECK("proto", id * 10 + 5, 0, valid_cnt)
                `CHECK("proto", id * 10 + 6, 1, err_cnt)
                if (err_cnt == 1) begin
                    n_checks = n_checks + 1;
                    if (err_t - t_last < 1 || err_t - t_last > 6) begin
                        n_fail = n_fail + 1;
                        if (n_fail <= 20) $display("TB_FAIL tag=timing case=%0d exp=%0d got=%0d", id * 10 + 7, t_last + 3, err_t);
                    end
                end
            end
        end
    endtask

    reg [7:0] b8, hold;
    initial begin
        rst_n = 0; ps2_clk = 0; ps2_data = 0;
        repeat (4) @(negedge clk);
        `CHECK("reset", 1, 1'b0, valid)
        `CHECK("reset", 2, 1'b0, err)
        ps2_clk = 1; ps2_data = 1; rst_n = 1;
        repeat (6) @(negedge clk);

        frame(8'h1C, 1, 1, 20, 0, 0, 1, 1);
        frame(8'h00, 1, 1, 20, 0, 0, 2, 1);
        frame(8'hFF, 1, 1, 20, 0, 0, 3, 1);
        frame(8'hF0, 1, 1, 8,  0, 0, 4, 1);     // fastest allowed clock
        for (i = 0; i < 10; i = i + 1) frame($random(seed), 1, 1, 8 + ({$random(seed)} % 20), 0, 0, 10 + i, 1);
        // parity / stop errors
        hold = cap;
        frame(8'h5A, 0, 1, 20, 0, 0, 30, 0);
        `CHECK("func", 300, hold, data)                       // data unchanged on error
        frame(8'hA5, 1, 0, 20, 0, 0, 31, 0);
        frame(8'h3C, 0, 0, 20, 0, 0, 32, 0);
        for (i = 0; i < 4; i = i + 1) frame($random(seed), 0, 1, 12, 0, 0, 40 + i, 0);
        frame(8'h77, 1, 1, 20, 0, 0, 50, 1);                  // alive after errors
        // gap inside a frame shorter than TIMEOUT: still received (edge-to-edge gap = 2*hp + gap_len)
        frame(8'h99, 1, 1, 12, 4, TO - 30 - 24, 60, 1);
        frame(8'h66, 1, 1, 12, 7, TO - 1 - 24, 61, 1);       // exactly TIMEOUT-1: must still be received
        frame(8'h66, 1, 1, 12, 7, TO + 2 - 24, 62, 2);       // TIMEOUT+2: must be dropped silently
        frame(8'h6A, 1, 1, 12, 2, TO + 40 - 24, 63, 2);
        frame(8'hD2, 1, 1, 20, 0, 0, 64, 1);
        // aborted frame: 5 bits then idle longer than TIMEOUT -> silent, next frame fine
        @(negedge clk); valid_cnt = 0; err_cnt = 0;
        bit_out(0, 20); bit_out(1, 20); bit_out(0, 20); bit_out(1, 20); bit_out(1, 20);
        ps2_data = 1; repeat (TO + 20) @(negedge clk);
        `CHECK("proto", 700, 0, valid_cnt)
        `CHECK("proto", 701, 0, err_cnt)
        frame(8'hE7, 1, 1, 20, 0, 0, 71, 1);
        // clock edges with data high (no start bit) and data glitch without clock -> nothing
        @(negedge clk); valid_cnt = 0; err_cnt = 0;
        for (i = 0; i < 11; i = i + 1) bit_out(1, 15);
        ps2_data = 0; repeat (30) @(negedge clk); ps2_data = 1; repeat (30) @(negedge clk);
        `CHECK("proto", 800, 0, valid_cnt)
        `CHECK("proto", 801, 0, err_cnt)
        frame(8'h42, 1, 1, 20, 0, 0, 81, 1);
        // reset in the middle of a frame
        @(negedge clk); bit_out(0, 20); bit_out(1, 20); bit_out(1, 20);
        rst_n = 0; ps2_clk = 1; ps2_data = 1; repeat (2) @(negedge clk);
        `CHECK("reset", 900, 1'b0, valid)
        `CHECK("reset", 901, 1'b0, err)
        rst_n = 1; repeat (6) @(negedge clk);
        frame(8'h2B, 1, 1, 20, 0, 0, 91, 1);
        `CHECK("proto", 950, 0, both)
        `CHECK("proto", 951, 0, wide)
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
