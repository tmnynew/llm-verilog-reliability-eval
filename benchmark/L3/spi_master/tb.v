// Transaction-level testbench for the SPI master: mode-0 slave model, timing/protocol monitor, second CLK_DIV instance
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
    // second instance with CLK_DIV = 2 in loopback (mosi -> miso)
    reg        start2 = 0;
    reg  [7:0] tx2 = 0;
    wire [7:0] rx2;
    wire       busy2, done2, sclk2, mosi2, cs2;
    spi_master #(.CLK_DIV(2)) dut2 (.clk(clk), .rst_n(rst_n), .start(start2), .tx_data(tx2), .rx_data(rx2),
                                    .busy(busy2), .done(done2), .sclk(sclk2), .mosi(mosi2), .miso(mosi2), .cs_n(cs2));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, cyc = 0;
    always @(negedge clk) cyc = cyc + 1;

    // ---------------- slave model (mode 0) ----------------
    reg [7:0] slv_tx = 0, slv_sh = 0, slv_rx = 0;
    reg       miso_r = 0;
    integer   slv_bits = 0;
    assign miso = miso_r;
    always @(negedge cs_n) begin slv_sh = slv_tx; miso_r = slv_tx[7]; slv_bits = 0; end
    always @(posedge sclk) if (cs_n === 1'b0) begin slv_rx = {slv_rx[6:0], mosi}; slv_bits = slv_bits + 1; end
    always @(negedge sclk) if (cs_n === 1'b0) begin slv_sh = {slv_sh[6:0], 1'b0}; miso_r = slv_sh[7]; end

    // ---------------- protocol monitor ----------------
    integer rise_cnt = 0, last_rise = -1, bad_timing = 0, bad_proto = 0, done_cnt = 0, cs_rises = 0, cs_fall_t = -1;
    reg     sclk_p = 0, cs_p = 1, done_p = 0;
    always @(negedge clk) if (rst_n) begin
        if (cs_p === 1'b1 && cs_n === 1'b0) begin cs_fall_t = cyc; rise_cnt = 0; last_rise = -1; end
        if (cs_p === 1'b0 && cs_n === 1'b1) cs_rises = cs_rises + 1;
        if (sclk_p === 1'b0 && sclk === 1'b1) begin
            if (cs_n !== 1'b0) bad_proto = bad_proto + 1;                                     // sclk while deselected
            if (last_rise >= 0 && cyc - last_rise != 2 * DIV) bad_timing = bad_timing + 1;   // period
            if (last_rise < 0 && (cyc - cs_fall_t < DIV || cyc - cs_fall_t > DIV + 1)) bad_timing = bad_timing + 1;
            last_rise = cyc; rise_cnt = rise_cnt + 1;
        end
        if (cs_n === 1'b1 && sclk !== 1'b0) bad_proto = bad_proto + 1;                        // idle low
        if (done === 1'b1) begin done_cnt = done_cnt + 1; if (done_p === 1'b1) bad_proto = bad_proto + 1; end
        if (done_p === 1'b1) begin
            if (busy !== 1'b0) bad_proto = bad_proto + 1;
            if (cs_n !== 1'b1) bad_proto = bad_proto + 1;
        end
        sclk_p = sclk; cs_p = cs_n; done_p = done;
    end else begin sclk_p = 0; cs_p = 1; done_p = 0; end

    // dut2 monitor: sclk2 period must be 4 cycles
    integer last_rise2 = -1, bad2 = 0, rise2 = 0;
    reg     sclk2_p = 0;
    always @(negedge clk) if (rst_n) begin
        if (sclk2_p === 1'b0 && sclk2 === 1'b1) begin
            if (last_rise2 >= 0 && cs2 === 1'b0 && cyc - last_rise2 != 4) bad2 = bad2 + 1;
            last_rise2 = cyc; rise2 = rise2 + 1;
        end
        if (cs2 === 1'b1) last_rise2 = -1;
        sclk2_p = sclk2;
    end

    task xfer;
        input [7:0] tx, slave_byte;
        input integer id;
        integer t0;
        begin
            @(negedge clk); slv_tx = slave_byte; tx_data = tx; start = 1;
            @(negedge clk); start = 0; tx_data = ~tx;             // tx_data was latched
            `CHECK("proto", id * 10 + 1, 1'b1, busy)
            `CHECK("proto", id * 10 + 2, 1'b0, cs_n)
            t0 = cyc; done_cnt = 0; bad_timing = 0; bad_proto = 0;
            while (busy === 1'b1 && cyc - t0 < 16 * DIV + 8) @(negedge clk);
            `CHECK("timing", id * 10 + 3, 1'b0, busy)
            @(negedge clk); @(negedge clk);
            `CHECK("proto", id * 10 + 4, 1, done_cnt)
            `CHECK("proto", id * 10 + 5, 1'b1, cs_n)
            `CHECK("proto", id * 10 + 6, 8, rise_cnt)
            `CHECK("func", id * 10 + 7, tx, slv_rx)
            `CHECK("func", id * 10 + 8, slave_byte, rx_data)
            `CHECK("timing", id * 10 + 9, 0, bad_timing)
            `CHECK("proto", id * 10 + 10, 0, bad_proto)
        end
    endtask

    initial begin
        rst_n = 0; start = 1; tx_data = 8'h5A;
        repeat (3) @(negedge clk);
        `CHECK("reset", 1, 1'b0, busy)
        `CHECK("reset", 2, 1'b1, cs_n)
        `CHECK("reset", 3, 1'b0, sclk)
        `CHECK("reset", 4, 1'b0, done)
        start = 0; rst_n = 1;
        repeat (3) @(negedge clk);
        `CHECK("reset", 5, 1'b0, busy)                        // start during reset must not start a transfer

        xfer(8'h00, 8'hFF, 1);
        xfer(8'hFF, 8'h00, 2);
        xfer(8'hA5, 8'h3C, 3);
        xfer(8'h81, 8'h7E, 4);
        for (i = 0; i < 12; i = i + 1) xfer($random(seed), $random(seed), 10 + i);

        // start held high: back-to-back transfers with cs_n returning high in between
        @(negedge clk); slv_tx = 8'h96; tx_data = 8'h69; start = 1; cs_rises = 0; done_cnt = 0;
        while (done_cnt < 2) @(negedge clk);          // two transfers finished ...
        while (busy !== 1'b1) @(negedge clk);         // ... third one has started
        start = 0;
        while (busy === 1'b1) @(negedge clk);
        repeat (2) @(negedge clk);
        `CHECK("proto", 100, 3, done_cnt)
        `CHECK("proto", 101, 3, cs_rises)
        `CHECK("func", 102, 8'h69, slv_rx)
        `CHECK("func", 103, 8'h96, rx_data)

        // start pulse while busy is ignored
        @(negedge clk); slv_tx = 8'hC3; tx_data = 8'h3C; start = 1;
        @(negedge clk); start = 0; done_cnt = 0;
        repeat (3 * DIV) @(negedge clk);
        start = 1; tx_data = 8'h00; @(negedge clk); start = 0;
        while (busy === 1'b1) @(negedge clk);
        repeat (2) @(negedge clk);
        `CHECK("proto", 110, 1, done_cnt)
        `CHECK("proto", 111, 8, rise_cnt)
        `CHECK("func", 112, 8'h3C, slv_rx)
        `CHECK("func", 113, 8'hC3, rx_data)
        repeat (3 * DIV) @(negedge clk);
        `CHECK("proto", 114, 1, done_cnt)                     // no second transfer

        // reset in the middle of a transfer
        @(negedge clk); slv_tx = 8'h11; tx_data = 8'h22; start = 1;
        @(negedge clk); start = 0;
        repeat (5 * DIV) @(negedge clk);
        rst_n = 0; done_cnt = 0;
        repeat (2) @(negedge clk);
        `CHECK("reset", 120, 1'b0, busy)
        `CHECK("reset", 121, 1'b1, cs_n)
        `CHECK("reset", 122, 1'b0, sclk)
        rst_n = 1;
        repeat (2) @(negedge clk);
        `CHECK("reset", 123, 0, done_cnt)
        xfer(8'h55, 8'hAA, 130);

        // second instance (CLK_DIV = 2) loopback
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk); tx2 = $random(seed); start2 = 1;
            @(negedge clk); start2 = 0;
            while (busy2 === 1'b1) @(negedge clk);
            repeat (2) @(negedge clk);
            `CHECK("func", 200 + i, tx2, rx2)
        end
        `CHECK("timing", 210, 0, bad2)
        `CHECK("proto", 211, 32, rise2)
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
