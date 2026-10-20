// Transaction-level testbench for the AXI4-Lite slave: master model with configurable channel ordering/back-pressure, handshake monitor, register model
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
module tb_axi_lite_slave;
    localparam [31:0] ID = 32'h5A5A_0003;
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10, DECERR = 2'b11;
    reg         clk = 0, rst_n = 0;
    reg         awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    reg  [7:0]  awaddr = 0, araddr = 0;
    reg  [31:0] wdata = 0;
    reg  [3:0]  wstrb = 0;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;

    axi_lite_slave dut (.clk(clk), .rst_n(rst_n),
        .awvalid(awvalid), .awaddr(awaddr), .awready(awready),
        .wvalid(wvalid), .wdata(wdata), .wstrb(wstrb), .wready(wready),
        .bvalid(bvalid), .bresp(bresp), .bready(bready),
        .arvalid(arvalid), .araddr(araddr), .arready(arready),
        .rvalid(rvalid), .rdata(rdata), .rresp(rresp), .rready(rready));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, k, cyc = 0;
    always @(negedge clk) cyc = cyc + 1;

    // ---------------- protocol monitor (samples at negedge + 4 ns, after all tb drives) ----------------
    integer aw_acc = 0, w_acc = 0, ar_acc = 0, b_issued = 0, r_issued = 0, bad = 0;
    reg         bvalid_p = 0, rvalid_p = 0, bready_p = 0, rready_p = 0;
    reg  [1:0]  bresp_p = 0, rresp_p = 0;
    reg  [31:0] rdata_p = 0;
    always @(negedge clk) begin
        #4;
        if (rst_n) begin
            if (bvalid === 1'b1 && bvalid_p !== 1'b1) begin
                if (b_issued >= ((aw_acc < w_acc) ? aw_acc : w_acc)) bad = bad + 1;   // response without a request
                b_issued = b_issued + 1;
            end
            if (bvalid_p === 1'b1 && bready_p !== 1'b1 && (bvalid !== 1'b1 || bresp !== bresp_p)) bad = bad + 1;
            if (rvalid === 1'b1 && rvalid_p !== 1'b1) begin
                if (r_issued >= ar_acc) bad = bad + 1;
                r_issued = r_issued + 1;
            end
            if (rvalid_p === 1'b1 && rready_p !== 1'b1 && (rvalid !== 1'b1 || rresp !== rresp_p || rdata !== rdata_p)) bad = bad + 1;
            if (awvalid === 1'b1 && awready === 1'b1) aw_acc = aw_acc + 1;
            if (wvalid === 1'b1 && wready === 1'b1) w_acc = w_acc + 1;
            if (arvalid === 1'b1 && arready === 1'b1) ar_acc = ar_acc + 1;
        end else begin
            aw_acc = 0; w_acc = 0; ar_acc = 0; b_issued = 0; r_issued = 0;
        end
        bvalid_p = bvalid; rvalid_p = rvalid; bready_p = bready; rready_p = rready;
        bresp_p = bresp; rresp_p = rresp; rdata_p = rdata;
    end

    // ---------------- master model ----------------
    task drive_aw;
        input [7:0] a;
        begin
            awaddr = a; awvalid = 1; #1;
            while (awready !== 1'b1) begin @(negedge clk); #2; end
            @(negedge clk); #1; awvalid = 0; awaddr = ~a;
        end
    endtask
    task drive_w;
        input [31:0] d;
        input [3:0] s;
        begin
            wdata = d; wstrb = s; wvalid = 1; #1;
            while (wready !== 1'b1) begin @(negedge clk); #2; end
            @(negedge clk); #1; wvalid = 0; wdata = ~d; wstrb = ~s;
        end
    endtask
    task wait_b;                          // b_dly < 0: bready already high; 0: assert as soon as bvalid seen; >0: hold off
        input integer b_dly;
        input [1:0] exp_resp;
        input integer id;
        integer t0;
        reg [1:0] resp;
        begin
            t0 = cyc; #1;
            while (bvalid !== 1'b1 && cyc - t0 < 8) begin @(negedge clk); #2; end
            `CHECK("timing", id * 10 + 1, 1'b1, bvalid)
            resp = bresp;
            `CHECK("func", id * 10 + 2, exp_resp, resp)
            if (b_dly > 0) begin
                repeat (b_dly) begin @(negedge clk); #2; `CHECK("proto", id * 10 + 3, {1'b1, resp}, {bvalid, bresp}) end
            end
            if (b_dly >= 0) bready = 1;
            @(negedge clk); #2; bready = 0;
            `CHECK("proto", id * 10 + 4, 1'b0, bvalid)
        end
    endtask
    task axi_write;
        input [7:0] a;
        input [31:0] d;
        input [3:0] s;
        input integer aw_dly, w_dly, b_dly;
        input [1:0] exp_resp;
        input integer id;
        begin
            @(negedge clk); #1;
            if (b_dly < 0) bready = 1;
            fork
                begin repeat (aw_dly) @(negedge clk); #1; drive_aw(a); end
                begin repeat (w_dly) @(negedge clk); #1; drive_w(d, s); end
            join
            wait_b(b_dly, exp_resp, id);
        end
    endtask
    task axi_read;
        input [7:0] a;
        input integer r_dly;               // < 0: rready already high
        input [1:0] exp_resp;
        input [31:0] exp_data;
        input integer id;
        integer t0;
        reg [31:0] d;
        reg [1:0] resp;
        begin
            @(negedge clk); #1;
            if (r_dly < 0) rready = 1;
            araddr = a; arvalid = 1; #1;
            while (arready !== 1'b1) begin @(negedge clk); #2; end
            @(negedge clk); #1; arvalid = 0; araddr = ~a;
            t0 = cyc; #1;
            while (rvalid !== 1'b1 && cyc - t0 < 8) begin @(negedge clk); #2; end
            `CHECK("timing", id * 10 + 5, 1'b1, rvalid)
            d = rdata; resp = rresp;
            `CHECK("func", id * 10 + 6, exp_resp, resp)
            `CHECK("func", id * 10 + 7, exp_data, d)
            if (r_dly > 0) begin
                repeat (r_dly) begin @(negedge clk); #2; `CHECK("proto", id * 10 + 8, {1'b1, resp, d}, {rvalid, rresp, rdata}) end
            end
            if (r_dly >= 0) rready = 1;
            @(negedge clk); #2; rready = 0;
            `CHECK("proto", id * 10 + 9, 1'b0, rvalid)
        end
    endtask

    // ---------------- reference register model ----------------
    reg [31:0] mreg [0:3];
    function [1:0] exp_wresp;
        input [7:0] a;
        begin
            if (a[7:4] != 0) exp_wresp = DECERR;
            else if (a[3:2] == 2'd3) exp_wresp = SLVERR;
            else exp_wresp = OKAY;
        end
    endfunction
    task model_write;
        input [7:0] a;
        input [31:0] d;
        input [3:0] s;
        integer b;
        begin
            if (a[7:4] == 0 && a[3:2] != 2'd3)
                for (b = 0; b < 4; b = b + 1)
                    if (s[b]) mreg[a[3:2]][8*b +: 8] = d[8*b +: 8];
        end
    endtask
    task read_all;
        input integer id;
        begin
            axi_read(8'h00, 0, OKAY, mreg[0], id);
            axi_read(8'h04, 1, OKAY, mreg[1], id + 1);
            axi_read(8'h08, -1, OKAY, mreg[2], id + 2);
            axi_read(8'h0C, 2, OKAY, ID, id + 3);
        end
    endtask

    reg [7:0] ra; reg [31:0] rd_; reg [3:0] rs;
    initial begin
        mreg[0] = 0; mreg[1] = 0; mreg[2] = 0; mreg[3] = ID;
        rst_n = 0;
        repeat (3) @(negedge clk); #2;
        `CHECK("reset", 1, 1'b0, bvalid)
        `CHECK("reset", 2, 1'b0, rvalid)
        rst_n = 1;
        @(negedge clk);
        read_all(10);

        // basic writes with different channel orderings and bready behaviour
        axi_write(8'h00, 32'hDEADBEEF, 4'hF, 0, 1, 0, OKAY, 20);  model_write(8'h00, 32'hDEADBEEF, 4'hF);
        axi_write(8'h04, 32'h12345678, 4'hF, 1, 0, 2, OKAY, 21);  model_write(8'h04, 32'h12345678, 4'hF);
        axi_write(8'h08, 32'hCAFEF00D, 4'hF, 0, 0, -1, OKAY, 22); model_write(8'h08, 32'hCAFEF00D, 4'hF);
        axi_write(8'h04, 32'hA5A5A5A5, 4'hF, 3, 0, 5, OKAY, 23);  model_write(8'h04, 32'hA5A5A5A5, 4'hF);
        read_all(30);
        // byte strobes
        axi_write(8'h00, 32'h11223344, 4'b0001, 0, 0, 0, OKAY, 40);  model_write(8'h00, 32'h11223344, 4'b0001);
        axi_write(8'h00, 32'h55667788, 4'b1100, 0, 2, 0, OKAY, 41);  model_write(8'h00, 32'h55667788, 4'b1100);
        axi_write(8'h08, 32'h99AABBCC, 4'b0110, 2, 0, 1, OKAY, 42);  model_write(8'h08, 32'h99AABBCC, 4'b0110);
        axi_write(8'h04, 32'hFFFFFFFF, 4'b0000, 0, 0, 0, OKAY, 43);  model_write(8'h04, 32'hFFFFFFFF, 4'b0000);
        read_all(50);
        // address bits [1:0] ignored
        axi_write(8'h06, 32'h0BADF00D, 4'hF, 0, 0, 0, OKAY, 60);  model_write(8'h06, 32'h0BADF00D, 4'hF);
        axi_read(8'h05, 0, OKAY, mreg[1], 61);
        axi_read(8'h0A, 0, OKAY, mreg[2], 62);
        axi_read(8'h0F, 0, OKAY, ID, 63);
        // read-only ID register
        axi_write(8'h0C, 32'hFFFFFFFF, 4'hF, 0, 0, 0, SLVERR, 70);
        axi_write(8'h0C, 32'h00000000, 4'h1, 1, 0, 3, SLVERR, 71);
        axi_read(8'h0C, 0, OKAY, ID, 72);
        // unmapped addresses
        axi_write(8'h10, 32'h01010101, 4'hF, 0, 0, 0, DECERR, 80);
        axi_write(8'h40, 32'h02020202, 4'hF, 0, 1, -1, DECERR, 81);
        axi_write(8'hFC, 32'h03030303, 4'hF, 1, 0, 2, DECERR, 82);
        axi_write(8'h84, 32'h04040404, 4'hF, 0, 0, 0, DECERR, 86);   // only bit 7 set: must not alias onto REG1
        axi_write(8'h20, 32'h05050505, 4'h3, 0, 0, 1, DECERR, 87);
        axi_read(8'h10, 0, DECERR, 32'd0, 83);
        axi_read(8'h80, 3, DECERR, 32'd0, 84);
        axi_read(8'hFC, -1, DECERR, 32'd0, 85);
        read_all(90);
        // random traffic
        for (i = 0; i < 24; i = i + 1) begin
            k = {$random(seed)} % 10;
            ra = (k < 7) ? {4'd0, k[1:0], 2'd0} : (k == 7) ? 8'h0C : {$random(seed)} | 8'h10;
            ra[1:0] = $random(seed);
            rd_ = $random(seed); rs = $random(seed);
            axi_write(ra, rd_, rs, {$random(seed)} % 3, {$random(seed)} % 3, ({$random(seed)} % 4) - 1, exp_wresp(ra), 100 + i);
            model_write(ra, rd_, rs);
            axi_read(ra, ({$random(seed)} % 4) - 1, (ra[7:4] != 0) ? DECERR : OKAY, (ra[7:4] != 0) ? 32'd0 : mreg[ra[3:2]], 130 + i);
        end
        read_all(160);
        // read while a write waits for its W beat
        @(negedge clk); #1;
        drive_aw(8'h08);
        axi_read(8'h04, 0, OKAY, mreg[1], 170);
        repeat (3) @(negedge clk); #2;
        `CHECK("proto", 1710, 1'b0, bvalid)                    // no response before W
        drive_w(32'h76543210, 4'hF); model_write(8'h08, 32'h76543210, 4'hF);
        wait_b(1, OKAY, 172);
        axi_read(8'h08, 0, OKAY, mreg[2], 173);
        // W first, AR in between
        @(negedge clk); #1;
        drive_w(32'h0F0F0F0F, 4'hF);
        axi_read(8'h00, 1, OKAY, mreg[0], 175);
        drive_aw(8'h00); model_write(8'h00, 32'h0F0F0F0F, 4'hF);
        wait_b(0, OKAY, 176);
        read_all(180);
        `CHECK("proto", 190, 0, bad)

        // reset with a response pending
        @(negedge clk); #1;
        fork drive_aw(8'h04); drive_w(32'h13579BDF, 4'hF); join
        @(negedge clk); @(negedge clk); #2;
        `CHECK("proto", 200, 1'b1, bvalid)
        rst_n = 0;
        repeat (2) @(negedge clk); #2;
        `CHECK("reset", 201, 1'b0, bvalid)
        `CHECK("reset", 202, 1'b0, rvalid)
        rst_n = 1; mreg[0] = 0; mreg[1] = 0; mreg[2] = 0;
        @(negedge clk);
        read_all(210);
        axi_write(8'h04, 32'h2468ACE0, 4'hF, 0, 0, 0, OKAY, 220); model_write(8'h04, 32'h2468ACE0, 4'hF);
        read_all(230);
        `CHECK("proto", 240, 0, bad)
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
