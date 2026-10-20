// Transaction-level testbench for the oversampled SPI slave: mode-0 master model with variable sclk period, valid-window check
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
module tb_spi_slave;
    reg        clk = 0, rst_n = 0, sclk = 0, cs_n = 1, mosi = 0;
    reg  [7:0] tx_data = 0;
    wire [7:0] rx_data;
    wire       miso, rx_valid;

    spi_slave dut (.clk(clk), .rst_n(rst_n), .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso),
                   .tx_data(tx_data), .rx_data(rx_data), .rx_valid(rx_valid));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, cyc = 0;
    always @(negedge clk) cyc = cyc + 1;

    // rx_valid monitor
    integer   valid_cnt = 0, valid_t = -1, wide = 0, t8 = -1;
    reg [7:0] cap0 = 0, cap1 = 0;
    reg       valid_p = 0;
    always @(negedge clk) begin
        if (rx_valid === 1'b1) begin
            if (valid_p === 1'b1) wide = wide + 1;
            else begin
                if (valid_cnt == 0) cap0 = rx_data; else cap1 = rx_data;
                valid_cnt = valid_cnt + 1; valid_t = cyc;
            end
        end
        valid_p = rx_valid;
    end

    // master model: one byte, half period hp (>= 8)
    reg [7:0] got;
    task m_byte;
        input [7:0] mbyte;
        input integer hp;
        integer b;
        begin
            mosi = mbyte[7];
            for (b = 7; b >= 0; b = b - 1) begin
                got[b] = miso;                  // master samples right at the rising edge
                sclk = 1; if (b == 0) t8 = cyc;
                repeat (hp) @(negedge clk);
                sclk = 0;
                repeat (2) @(negedge clk);
                if (b > 0) mosi = mbyte[b - 1];
                repeat (hp - 2) @(negedge clk);
            end
        end
    endtask

    task xfer;                                   // full transaction: cs low, one byte, cs high, checks
        input [7:0] mbyte, sbyte;
        input integer hp;
        input integer id;
        begin
            @(negedge clk); tx_data = sbyte; cs_n = 0; valid_cnt = 0; wide = 0;
            repeat (hp / 2) @(negedge clk);
            tx_data = ~sbyte;                    // later changes must not matter
            repeat (hp - hp / 2) @(negedge clk);
            m_byte(mbyte, hp);
            repeat (hp) @(negedge clk);
            cs_n = 1;
            repeat (8) @(negedge clk);
            `CHECK("proto", id * 10 + 1, 1, valid_cnt)
            `CHECK("func",  id * 10 + 2, mbyte, cap0)
            `CHECK("func",  id * 10 + 3, sbyte, got)
            `CHECK("proto", id * 10 + 4, 0, wide)
            if (valid_cnt == 1) begin
                n_checks = n_checks + 1;
                if (valid_t - t8 < 1 || valid_t - t8 > 8) begin
                    n_fail = n_fail + 1;
                    if (n_fail <= 20) $display("TB_FAIL tag=timing case=%0d exp=%0d got=%0d", id * 10 + 5, t8 + 3, valid_t);
                end
            end
            `CHECK("proto", id * 10 + 6, 1'b0, miso)   // deselected -> 0
        end
    endtask

    initial begin
        rst_n = 0; cs_n = 0; sclk = 1;
        repeat (4) @(negedge clk);
        `CHECK("reset", 1, 1'b0, rx_valid)
        `CHECK("reset", 2, 1'b0, miso)
        cs_n = 1; sclk = 0; rst_n = 1;
        repeat (6) @(negedge clk);
        `CHECK("reset", 3, 1'b0, miso)
        `CHECK("reset", 4, 0, valid_cnt)

        xfer(8'h00, 8'hFF, 8, 1);
        xfer(8'hFF, 8'h00, 8, 2);
        xfer(8'hA5, 8'h5A, 8, 3);
        xfer(8'h81, 8'h7E, 12, 4);
        for (i = 0; i < 12; i = i + 1) xfer($random(seed), $random(seed), 8 + ({$random(seed)} % 7), 10 + i);

        // two bytes under one chip select
        @(negedge clk); tx_data = 8'h3C; cs_n = 0; valid_cnt = 0;
        repeat (8) @(negedge clk);
        m_byte(8'h12, 8);
        `CHECK("func", 100, 8'h3C, got)
        m_byte(8'h34, 8);
        repeat (8) @(negedge clk); cs_n = 1; repeat (8) @(negedge clk);
        `CHECK("proto", 101, 2, valid_cnt)
        `CHECK("func", 102, 8'h12, cap0)
        `CHECK("func", 103, 8'h34, cap1)

        // aborted byte (cs_n high after 3 bits) -> no rx_valid, next transfer fine
        @(negedge clk); tx_data = 8'hC3; cs_n = 0; valid_cnt = 0;
        repeat (8) @(negedge clk);
        mosi = 1; sclk = 1; repeat (8) @(negedge clk); sclk = 0; repeat (8) @(negedge clk);
        mosi = 0; sclk = 1; repeat (8) @(negedge clk); sclk = 0; repeat (8) @(negedge clk);
        mosi = 1; sclk = 1; repeat (8) @(negedge clk); sclk = 0; repeat (8) @(negedge clk);
        cs_n = 1; repeat (8) @(negedge clk);
        `CHECK("proto", 110, 0, valid_cnt)
        xfer(8'h96, 8'h69, 8, 111);

        // sclk edges while deselected are ignored
        @(negedge clk); valid_cnt = 0;
        for (i = 0; i < 8; i = i + 1) begin mosi = 1; sclk = 1; repeat (8) @(negedge clk); sclk = 0; repeat (8) @(negedge clk); end
        repeat (8) @(negedge clk);
        `CHECK("proto", 120, 0, valid_cnt)
        `CHECK("proto", 121, 1'b0, miso)
        xfer(8'h0F, 8'hF0, 9, 122);

        // reset in the middle of a byte
        @(negedge clk); tx_data = 8'hAA; cs_n = 0;
        repeat (8) @(negedge clk);
        mosi = 1; sclk = 1; repeat (8) @(negedge clk); sclk = 0; repeat (8) @(negedge clk);
        rst_n = 0; repeat (2) @(negedge clk);
        `CHECK("reset", 130, 1'b0, rx_valid)
        `CHECK("reset", 131, 1'b0, miso)
        rst_n = 1; sclk = 0; cs_n = 1; repeat (6) @(negedge clk);
        xfer(8'h55, 8'hAA, 8, 132);
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
