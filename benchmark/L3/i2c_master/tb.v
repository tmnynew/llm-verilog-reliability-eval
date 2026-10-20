// Transaction-level testbench for the I2C master: wired-AND bus with a reactive slave model, START/STOP and SCL-period monitor
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

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, cyc = 0;
    always @(negedge clk) cyc = cyc + 1;

    // ---------------- slave model: address SLV, one data register ----------------
    // Clocked at negedge clk with edge detection on the bus lines (the DUT drives scl_o/sda_o at
    // posedge clk, half a cycle earlier), so the model is race-free across simulators.
    reg [7:0] slv_mem = 0, s_sh = 0, s_addr_byte = 0;
    reg       slv_nack_data = 0, s_rw = 0, master_ack = 1;
    integer   s_state = 0, s_bit = 0, starts = 0, stops = 0, addr_seen = 0, wr_cnt = 0;
    reg       scl_q = 1, sda_q = 1;
    always @(negedge clk) begin
        if (rst_n) begin
            if (scl === 1'b1 && sda_q === 1'b1 && sda_i === 1'b0) begin starts = starts + 1; s_state = 1; s_bit = 0; sda_slv = 1; end   // START
            if (scl === 1'b1 && sda_q === 1'b0 && sda_i === 1'b1) begin stops = stops + 1; s_state = 0; sda_slv = 1; end     // STOP
            if (scl_q === 1'b0 && scl === 1'b1) case (s_state)                                                              // SCL rise
                1, 3: begin s_sh = {s_sh[6:0], sda_i}; s_bit = s_bit + 1; end
                6:    master_ack = sda_i;
                default: ;
            endcase
            if (scl_q === 1'b1 && scl === 1'b0) case (s_state)                                                              // SCL fall
                1: if (s_bit == 8) begin
                       s_addr_byte = s_sh; addr_seen = addr_seen + 1;
                       if (s_sh[7:1] == SLV) begin sda_slv = 0; s_rw = s_sh[0]; s_state = 2; end else s_state = 9;
                   end
                2: if (s_rw) begin s_sh = slv_mem; sda_slv = s_sh[7]; s_bit = 1; s_state = 5; end
                   else begin sda_slv = 1; s_bit = 0; s_state = 3; end
                3: if (s_bit == 8) begin slv_mem = s_sh; wr_cnt = wr_cnt + 1; sda_slv = slv_nack_data; s_state = 4; end
                4: begin sda_slv = 1; s_state = 9; end
                5: if (s_bit == 8) begin sda_slv = 1; s_state = 6; end
                   else begin s_sh = {s_sh[6:0], 1'b0}; sda_slv = s_sh[7]; s_bit = s_bit + 1; end
                6: s_state = 9;
                default: ;
            endcase
        end
        scl_q = scl; sda_q = sda_i;
    end

    // ---------------- protocol / timing monitor ----------------
    integer hi_changes = 0, scl_rises = 0, last_rise = -1, bad_timing = 0, done_cnt = 0, wide = 0;
    reg     scl_p = 1, done_p = 0;
    always @(sda_o) if (rst_n && scl_o === 1'b1) hi_changes = hi_changes + 1;      // only START and STOP allowed
    always @(negedge clk) if (rst_n) begin
        if (scl_p === 1'b0 && scl_o === 1'b1) begin
            if (last_rise >= 0 && cyc - last_rise != 4 * DIV) bad_timing = bad_timing + 1;
            last_rise = cyc; scl_rises = scl_rises + 1;
        end
        if (busy !== 1'b1) last_rise = -1;
        if (done === 1'b1) begin done_cnt = done_cnt + 1; if (done_p === 1'b1) wide = wide + 1; end
        scl_p = scl_o; done_p = done;
    end else begin scl_p = 1; done_p = 0; end

    task xact;
        input rw_i;
        input [6:0] a;
        input [7:0] wd, slave_val;
        input nack_data, exp_err;
        input integer exp_rises;
        input integer id;
        integer t0;
        begin
            @(negedge clk);
            slv_mem = slave_val; slv_nack_data = nack_data;
            starts = 0; stops = 0; addr_seen = 0; wr_cnt = 0; done_cnt = 0; hi_changes = 0; bad_timing = 0; scl_rises = 0; master_ack = 0;
            rw = rw_i; addr = a; wdata = wd; start = 1;
            @(negedge clk); start = 0; addr = ~a; wdata = ~wd; rw = ~rw_i;
            `CHECK("proto", id * 20 + 1, 1'b1, busy)
            t0 = cyc;
            while (busy === 1'b1 && cyc - t0 < 100 * DIV) @(negedge clk);
            `CHECK("timing", id * 20 + 2, 1'b0, busy)
            @(negedge clk); @(negedge clk);
            `CHECK("proto", id * 20 + 3, 1, done_cnt)
            `CHECK("proto", id * 20 + 4, 1, starts)
            `CHECK("proto", id * 20 + 5, 1, stops)
            `CHECK("proto", id * 20 + 6, 1, addr_seen)
            `CHECK("func",  id * 20 + 7, {a, rw_i}, s_addr_byte)
            `CHECK("func",  id * 20 + 8, exp_err, ack_err)
            `CHECK("proto", id * 20 + 9, exp_rises, scl_rises)
            if (!exp_err) begin
                if (rw_i) begin
                    `CHECK("func",  id * 20 + 10, slave_val, rdata)
                    `CHECK("proto", id * 20 + 11, 1'b1, master_ack)     // master must NACK the byte it read
                end else begin
                    `CHECK("func",  id * 20 + 12, wd, slv_mem)
                    `CHECK("proto", id * 20 + 13, 1, wr_cnt)
                end
            end else if (a != SLV) begin
                `CHECK("proto", id * 20 + 14, 0, wr_cnt)
                `CHECK("func",  id * 20 + 15, slave_val, slv_mem)
            end
            `CHECK("proto",  id * 20 + 16, 2, hi_changes)
            `CHECK("timing", id * 20 + 17, 0, bad_timing)
            `CHECK("proto",  id * 20 + 18, 2'b11, {scl_o, sda_o})
        end
    endtask

    reg [7:0] v;
    initial begin
        rst_n = 0; start = 1;
        repeat (3) @(negedge clk);
        `CHECK("reset", 1, 1'b0, busy)
        `CHECK("reset", 2, 2'b11, {scl_o, sda_o})
        `CHECK("reset", 3, 1'b0, done)
        `CHECK("reset", 4, 1'b0, ack_err)
        start = 0; rst_n = 1;
        repeat (3) @(negedge clk);
        `CHECK("reset", 5, 1'b0, busy)

        // writes and reads to the responding slave
        xact(0, SLV, 8'hA5, 8'h00, 0, 0, 19, 1);
        xact(1, SLV, 8'h00, 8'hA5, 0, 0, 19, 2);
        xact(0, SLV, 8'h00, 8'h00, 0, 0, 19, 3);
        xact(0, SLV, 8'hFF, 8'h00, 0, 0, 19, 4);
        xact(1, SLV, 8'h00, 8'hFF, 0, 0, 19, 5);
        xact(1, SLV, 8'h00, 8'h00, 0, 0, 19, 6);
        for (i = 0; i < 10; i = i + 1) begin
            v = $random(seed);
            xact(0, SLV, v, 8'h00, 0, 0, 19, 10 + i);
            xact(1, SLV, 8'h00, v, 0, 0, 19, 20 + i);
        end
        // address not acknowledged -> ack_err, early STOP, no data phase
        xact(0, 7'h51, 8'h12, 8'h34, 0, 1, 10, 40);
        xact(1, 7'h00, 8'h12, 8'h34, 0, 1, 10, 41);
        xact(0, 7'h7F, 8'h12, 8'h34, 0, 1, 10, 42);
        xact(1, 7'h28, 8'h12, 8'h34, 0, 1, 10, 43);      // SLV >> 1: shifted address must not match
        // data byte not acknowledged
        xact(0, SLV, 8'h5A, 8'h00, 1, 1, 19, 44);
        xact(0, SLV, 8'hC3, 8'h00, 0, 0, 19, 45);        // ack_err cleared by the next transaction
        // start pulse during a transaction is ignored
        @(negedge clk); slv_mem = 0; slv_nack_data = 0; addr_seen = 0; done_cnt = 0;
        rw = 0; addr = SLV; wdata = 8'h3C; start = 1;
        @(negedge clk); start = 0;
        repeat (10 * DIV) @(negedge clk);
        addr = 7'h11; wdata = 8'h00; start = 1; @(negedge clk); start = 0;
        while (busy === 1'b1) @(negedge clk);
        repeat (2) @(negedge clk);
        `CHECK("proto", 1000, 1, done_cnt)
        `CHECK("proto", 1001, 1, addr_seen)
        `CHECK("func", 1002, 8'h3C, slv_mem)
        repeat (10 * DIV) @(negedge clk);
        `CHECK("proto", 1003, 1, done_cnt)
        // reset in the middle of a transaction
        @(negedge clk); rw = 0; addr = SLV; wdata = 8'h77; start = 1;
        @(negedge clk); start = 0;
        repeat (30 * DIV) @(negedge clk);
        rst_n = 0; done_cnt = 0;
        repeat (2) @(negedge clk);
        `CHECK("reset", 1100, 1'b0, busy)
        `CHECK("reset", 1101, 2'b11, {scl_o, sda_o})
        s_state = 0; sda_slv = 1;
        rst_n = 1;
        repeat (3) @(negedge clk);
        `CHECK("reset", 1102, 0, done_cnt)
        xact(0, SLV, 8'h99, 8'h00, 0, 0, 19, 1110);
        xact(1, SLV, 8'h00, 8'h99, 0, 0, 19, 1111);
        `CHECK("proto", 1200, 0, wide)
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
