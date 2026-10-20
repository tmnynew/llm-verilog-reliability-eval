// Weak testbench (Exp. 2 baseline): TX - pulse tx_start twice and only watch tx_busy rise and fall again;
// RX - drive two well-timed frames and compare rx_data once rx_valid pulses. Not covered (on purpose): the TX
// line itself (start/stop bits, bit timing, data order), tx_start while busy, rx_valid pulse width / latency,
// baud jitter, back-to-back frames, framing errors (rx_err is never checked), glitches, loopback, mid-run reset
//
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

module tb_uart;
    localparam CPB = 16;
    reg        clk = 0, rst_n = 0;
    reg        tx_start = 0;
    reg  [7:0] tx_data = 0;
    wire       tx_busy, tx;
    reg        rx = 1;
    wire [7:0] rx_data;
    wire       rx_valid, rx_err;

    uart dut (.clk(clk), .rst_n(rst_n), .tx_start(tx_start), .tx_data(tx_data), .tx_busy(tx_busy), .tx(tx),
              .rx(rx), .rx_data(rx_data), .rx_valid(rx_valid), .rx_err(rx_err));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, i, w;
    integer n_valid = 0;
    reg [7:0] last_rx;
    always @(negedge clk) if (rx_valid === 1'b1) begin n_valid = n_valid + 1; last_rx = rx_data; end

    task send_and_wait;              // start a frame, expect busy to rise, then wait for it to fall
        input [7:0] b;
        input integer id;
        begin
            @(negedge clk);
            tx_data = b; tx_start = 1;
            @(negedge clk);
            tx_start = 0;
            `CHECK("proto", id, 1'b1, tx_busy)
            w = 0;
            while (tx_busy && w < 20 * CPB) begin @(negedge clk); w = w + 1; end
            `CHECK("proto", id + 1, 1'b0, tx_busy)
        end
    endtask

    task rx_frame;                   // 8N1 frame with exact bit timing
        input [7:0] b;
        integer bit_i;
        begin
            @(negedge clk);
            for (bit_i = 0; bit_i < 10; bit_i = bit_i + 1) begin
                rx = (bit_i == 0) ? 1'b0 : (bit_i == 9) ? 1'b1 : b[bit_i - 1];
                repeat (CPB) @(negedge clk);
            end
            rx = 1;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);

        // ---- TX: two bytes, busy handshake only ----
        send_and_wait(8'h55, 10);
        send_and_wait(8'hA3, 20);

        // ---- RX: two frames, data compare ----
        n_valid = 0;
        rx_frame(8'h5A);
        repeat (2 * CPB) @(negedge clk);
        `CHECK("proto", 100, 1, n_valid)
        `CHECK("func", 101, 8'h5A, last_rx)
        n_valid = 0;
        rx_frame(8'h0F);
        repeat (2 * CPB) @(negedge clk);
        `CHECK("proto", 110, 1, n_valid)
        `CHECK("func", 111, 8'h0F, last_rx)

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
