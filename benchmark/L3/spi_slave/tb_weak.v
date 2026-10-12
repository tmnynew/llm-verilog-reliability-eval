// Weak testbench (Exp. 2 baseline): one byte at a single comfortable sclk rate; checks that rx_valid appears once
// and rx_data matches. No miso check, no valid-timing/width check, no multi-byte select, no aborted byte,
// no edges while deselected, no tx_data change after cs fall, no mid-byte reset - see docs/testbench_protocol.md
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

    integer n_checks = 0, n_fail = 0, seed = `SEED, b;
    integer   valid_cnt = 0;
    reg [7:0] cap = 0;
    always @(negedge clk) if (rx_valid === 1'b1) begin valid_cnt = valid_cnt + 1; cap = rx_data; end

    task m_byte;                                 // master drives one byte, half period 8 cycles
        input [7:0] mbyte;
        begin
            for (b = 7; b >= 0; b = b - 1) begin
                mosi = mbyte[b];
                repeat (8) @(negedge clk);
                sclk = 1;
                repeat (8) @(negedge clk);
                sclk = 0;
            end
        end
    endtask

    initial begin
        rst_n = 0; cs_n = 1; sclk = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (6) @(negedge clk);

        @(negedge clk); tx_data = 8'h5A; cs_n = 0; valid_cnt = 0;
        repeat (8) @(negedge clk);
        m_byte(8'hA5);
        repeat (8) @(negedge clk);
        cs_n = 1;
        repeat (8) @(negedge clk);
        `CHECK("proto", 1, 1, valid_cnt)
        `CHECK("func",  2, 8'hA5, cap)
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
