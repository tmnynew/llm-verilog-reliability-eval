// Weak testbench (Exp. 2 baseline): two nominal transfers with a mode-0 slave model, data compared only after
// busy falls. No sclk period/phase monitor, no cs_n/done protocol checks, no back-to-back, no start-while-busy,
// no mid-transfer reset, no second CLK_DIV instance
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
module tb_spi_master;
    localparam DIV = 4;
    reg        clk = 0, rst_n = 0, start = 0;
    reg  [7:0] tx_data = 0;
    wire [7:0] rx_data;
    wire       busy, done, sclk, mosi, cs_n, miso;

    spi_master #(.CLK_DIV(DIV)) dut (.clk(clk), .rst_n(rst_n), .start(start), .tx_data(tx_data), .rx_data(rx_data),
                                     .busy(busy), .done(done), .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, t;

    // slave model (mode 0)
    reg [7:0] slv_tx = 0, slv_sh = 0, slv_rx = 0;
    reg       miso_r = 0;
    assign miso = miso_r;
    always @(negedge cs_n) begin slv_sh = slv_tx; miso_r = slv_tx[7]; end
    always @(posedge sclk) if (cs_n === 1'b0) slv_rx = {slv_rx[6:0], mosi};
    always @(negedge sclk) if (cs_n === 1'b0) begin slv_sh = {slv_sh[6:0], 1'b0}; miso_r = slv_sh[7]; end

    task xfer;
        input [7:0] tx, slave_byte;
        input integer id;
        begin
            @(negedge clk); slv_tx = slave_byte; tx_data = tx; start = 1;
            @(negedge clk); start = 0;
            `CHECK("proto", id * 10 + 1, 1'b1, busy)
            t = 0;
            while (busy === 1'b1 && t < 200) begin @(negedge clk); t = t + 1; end
            `CHECK("timing", id * 10 + 2, 1'b0, busy)
            repeat (2) @(negedge clk);
            `CHECK("func", id * 10 + 3, tx, slv_rx)
            `CHECK("func", id * 10 + 4, slave_byte, rx_data)
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (3) @(negedge clk);
        `CHECK("reset", 1, 1'b0, busy)
        `CHECK("reset", 2, 1'b1, cs_n)
        rst_n = 1;
        repeat (3) @(negedge clk);
        xfer(8'hA5, 8'h3C, 1);
        xfer(8'h5A, 8'hC3, 2);
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
