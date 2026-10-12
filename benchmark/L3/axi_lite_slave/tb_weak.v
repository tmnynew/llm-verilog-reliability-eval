// Weak testbench (Exp. 2 baseline): two full-word writes (AW and W driven together, bready high) and three
// reads (two registers + ID). No byte strobes, no DECERR/SLVERR addresses, no channel reordering or
// back-pressure, no protocol monitor, no reset-value or mid-run reset check - see docs/testbench_protocol.md
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
    localparam [1:0] OKAY = 2'b00;
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

    integer n_checks = 0, n_fail = 0, seed = `SEED, t;
    reg aw_ok, w_ok, ar_ok;

    task axi_write;
        input [7:0] a;
        input [31:0] d;
        input integer id;
        begin
            @(negedge clk);
            awaddr = a; awvalid = 1; wdata = d; wstrb = 4'hF; wvalid = 1; bready = 1;
            t = 0;
            while ((awvalid || wvalid) && t < 20) begin
                #1; aw_ok = awready; w_ok = wready;
                @(negedge clk); t = t + 1;
                if (aw_ok) awvalid = 0;
                if (w_ok)  wvalid  = 0;
            end
            `CHECK("handshake", id * 10 + 1, 2'b00, {awvalid, wvalid})
            t = 0;
            while (bvalid !== 1'b1 && t < 20) begin @(negedge clk); t = t + 1; end
            `CHECK("handshake", id * 10 + 2, 1'b1, bvalid)
            `CHECK("func", id * 10 + 3, OKAY, bresp)
            @(negedge clk); bready = 0;
        end
    endtask

    task axi_read;
        input [7:0] a;
        input [31:0] exp_data;
        input integer id;
        begin
            @(negedge clk);
            araddr = a; arvalid = 1; rready = 1;
            t = 0;
            while (arvalid && t < 20) begin
                #1; ar_ok = arready;
                @(negedge clk); t = t + 1;
                if (ar_ok) arvalid = 0;
            end
            `CHECK("handshake", id * 10 + 1, 1'b0, arvalid)
            t = 0;
            while (rvalid !== 1'b1 && t < 20) begin @(negedge clk); t = t + 1; end
            `CHECK("handshake", id * 10 + 2, 1'b1, rvalid)
            `CHECK("func", id * 10 + 3, OKAY, rresp)
            `CHECK("func", id * 10 + 4, exp_data, rdata)
            @(negedge clk); rready = 0;
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        axi_write(8'h00, 32'h12345678, 1);
        axi_write(8'h04, 32'h0ABCDEF0, 2);
        axi_read(8'h00, 32'h12345678, 3);
        axi_read(8'h04, 32'h0ABCDEF0, 4);
        axi_read(8'h0C, ID, 5);
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
