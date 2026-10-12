// Transaction-level testbench for the 8N1 UART: TX monitor, RX driver with jitter, loopback – see docs/testbench_protocol.md
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
    localparam CPB = 16;                 // CLKS_PER_BIT
    reg        clk = 0, rst_n = 0;
    reg        tx_start = 0;
    reg  [7:0] tx_data = 0;
    wire       tx_busy, tx;
    reg        rx_reg = 1, loopback = 0;
    wire       rx = loopback ? tx : rx_reg;
    wire [7:0] rx_data;
    wire       rx_valid, rx_err;

    uart dut (.clk(clk), .rst_n(rst_n), .tx_start(tx_start), .tx_data(tx_data), .tx_busy(tx_busy), .tx(tx),
              .rx(rx), .rx_data(rx_data), .rx_valid(rx_valid), .rx_err(rx_err));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, k;
    integer cyc = 0;
    always @(negedge clk) cyc = cyc + 1;

    // ================================================================== //
    // TX monitor: samples `tx` at bit centres, checks framing and length
    // ================================================================== //
    reg [7:0] tx_exp_q [0:255];  integer tx_exp_wr = 0, tx_exp_rd = 0;   // bytes we asked the DUT to send
    integer   tx_frames_seen = 0;
    reg       tx_prev = 1;
    integer   mon_state = 0, mon_t0 = 0, mon_bit = 0;
    reg [7:0] mon_byte;
    reg       busy_prev = 0;
    integer   busy_rise_cyc = -1;

    always @(negedge clk) if (rst_n) begin
        // start-bit detection
        if (mon_state == 0 && tx_prev === 1'b1 && tx === 1'b0) begin
            mon_state = 1; mon_t0 = cyc; mon_bit = 0;
        end else if (mon_state == 1) begin
            // sample at t0 + CPB/2 + CPB*(bit+1)  → data bits 0..7, then stop
            if (cyc == mon_t0 + CPB / 2 + CPB * (mon_bit + 1)) begin
                if (mon_bit < 8) mon_byte[mon_bit] = tx;
                else begin
                    `CHECK("proto", 1000 + tx_frames_seen, 1'b1, tx)               // stop bit must be 1
                    if (tx_exp_rd < tx_exp_wr) begin
                        `CHECK("func", 2000 + tx_frames_seen, tx_exp_q[tx_exp_rd], mon_byte)
                        tx_exp_rd = tx_exp_rd + 1;
                    end else begin
                        `CHECK("proto", 3000 + tx_frames_seen, 0, 1)               // unexpected frame
                    end
                    tx_frames_seen = tx_frames_seen + 1;
                    mon_state = 0;
                end
                mon_bit = mon_bit + 1;
            end
            // start bit must stay low for its whole width (sample near the end of it)
            if (cyc == mon_t0 + CPB - 2) `CHECK("proto", 4000 + tx_frames_seen, 1'b0, tx)
        end
        // busy handshake: rises with the start bit, falls 10 bits later (±2 cycles)
        if (busy_prev === 1'b0 && tx_busy === 1'b1) busy_rise_cyc = cyc;
        if (busy_prev === 1'b1 && tx_busy === 1'b0) begin
            k = cyc - busy_rise_cyc;
            if (k < 10 * CPB - 2 || k > 10 * CPB + 2) begin
                n_checks = n_checks + 1; n_fail = n_fail + 1;
                if (n_fail <= 20) $display("TB_FAIL tag=proto case=%0d exp=%0d got=%0d", 5000 + tx_frames_seen, 10 * CPB, k);
            end else n_checks = n_checks + 1;
        end
        tx_prev = tx; busy_prev = tx_busy;
    end else begin
        tx_prev = 1; busy_prev = 0; mon_state = 0;
    end

    task send_byte;                       // wait for idle, pulse tx_start for one cycle
        input [7:0] b;
        begin
            @(negedge clk);
            while (tx_busy) @(negedge clk);
            tx_data = b; tx_start = 1;
            tx_exp_q[tx_exp_wr] = b; tx_exp_wr = tx_exp_wr + 1;
            @(negedge clk);
            tx_start = 0;
            `CHECK("proto", 6000 + tx_exp_wr, 1'b1, tx_busy)   // busy must be visible one cycle after tx_start
            `CHECK("proto", 6500 + tx_exp_wr, 1'b0, tx)        // and the start bit has begun
        end
    endtask

    // ================================================================== //
    // RX monitor: captures rx_valid / rx_err pulses with timestamps
    // ================================================================== //
    reg [7:0] rx_got_q [0:255];  integer rx_got_wr = 0, rx_got_rd = 0;
    integer   rx_got_t  [0:255];
    integer   rx_err_count = 0, rx_err_t = -1;
    reg       valid_prev = 0, err_prev = 0;
    always @(negedge clk) begin
        if (rx_valid === 1'b1) begin
            if (valid_prev === 1'b1) begin `CHECK("timing", 7000 + rx_got_wr, 1, 2) end  // pulse wider than 1 cycle
            else begin rx_got_q[rx_got_wr] = rx_data; rx_got_t[rx_got_wr] = cyc; rx_got_wr = rx_got_wr + 1; end
        end
        if (rx_err === 1'b1 && err_prev !== 1'b1) begin rx_err_count = rx_err_count + 1; rx_err_t = cyc; end
        valid_prev = rx_valid; err_prev = rx_err;
    end

    // drive one frame on rx_reg. jitter: 0 exact, 1 alternate 15/17, 2 +1 on first 4 bits, 3 -1 on first 5 bits
    integer stop_mid_t;
    task rx_frame;
        input [7:0] b;
        input integer jitter;
        input stop_bit;
        integer w, bit_i, t_start;
        begin
            @(negedge clk);
            t_start = cyc;
            for (bit_i = 0; bit_i < 10; bit_i = bit_i + 1) begin
                case (jitter)
                    1: w = (bit_i[0]) ? CPB + 1 : CPB - 1;
                    2: w = (bit_i < 4) ? CPB + 1 : CPB;
                    3: w = (bit_i < 5) ? CPB - 1 : CPB;
                    default: w = CPB;
                endcase
                rx_reg = (bit_i == 0) ? 1'b0 : (bit_i == 9) ? stop_bit : b[bit_i - 1];
                if (bit_i == 9) stop_mid_t = cyc + w / 2;
                repeat (w) @(negedge clk);
            end
            rx_reg = 1;
        end
    endtask

    task expect_rx;                        // after a frame: exactly one new valid pulse, correct data, inside window
        input [7:0] b;
        input integer id;
        begin
            repeat (CPB) @(negedge clk);   // window: stop-bit centre + CPB/2, plus slack for the idle return
            `CHECK("proto", id, 1, rx_got_wr - rx_got_rd)
            if (rx_got_wr > rx_got_rd) begin
                `CHECK("func", id, b, rx_got_q[rx_got_rd])
                // window: actual stop-bit centre, minus the tolerated accumulated jitter, plus CPB/2 of latency
                if (rx_got_t[rx_got_rd] < stop_mid_t - (CPB / 2 - 2) || rx_got_t[rx_got_rd] > stop_mid_t + CPB / 2 + 1) begin
                    n_checks = n_checks + 1; n_fail = n_fail + 1;
                    if (n_fail <= 20) $display("TB_FAIL tag=timing case=%0d exp=%0d got=%0d", id, stop_mid_t, rx_got_t[rx_got_rd]);
                end else n_checks = n_checks + 1;
                rx_got_rd = rx_got_wr;
            end
        end
    endtask

    // ================================================================== //
    // Main sequence
    // ================================================================== //
    reg [7:0] b;
    integer errs_before;
    initial begin
        // ---- reset ----
        rx_reg = 1; tx_start = 1; tx_data = 8'h5A;
        repeat (4) @(negedge clk);
        `CHECK("reset", 1, 1'b1, tx)
        `CHECK("reset", 2, 1'b0, tx_busy)
        `CHECK("reset", 3, 1'b0, rx_valid)
        `CHECK("reset", 5, 1'b0, rx_err)
        tx_start = 0;
        rst_n = 1;
        repeat (3) @(negedge clk);
        `CHECK("reset", 4, 0, tx_frames_seen)       // tx_start during reset must not start a frame

        // ---- TX: a few bytes, including 00 / FF / 55 / AA ----
        send_byte(8'h00); send_byte(8'hFF); send_byte(8'h55); send_byte(8'hAA);
        for (i = 0; i < 12; i = i + 1) send_byte($random(seed));
        // tx_start while busy must be ignored
        send_byte(8'h3C);
        repeat (20) @(negedge clk);
        tx_start = 1; tx_data = 8'hC3; @(negedge clk); tx_start = 0;
        while (tx_busy) @(negedge clk);
        repeat (2 * CPB) @(negedge clk);
        `CHECK("proto", 10, tx_exp_wr, tx_frames_seen)

        // ---- RX: exact timing ----
        rx_frame(8'h00, 0, 1); expect_rx(8'h00, 100);
        rx_frame(8'hFF, 0, 1); expect_rx(8'hFF, 101);
        rx_frame(8'hA5, 0, 1); expect_rx(8'hA5, 102);
        for (i = 0; i < 8; i = i + 1) begin b = $random(seed); rx_frame(b, 0, 1); expect_rx(b, 110 + i); end
        // ---- RX: jittered timing ----
        for (i = 0; i < 6; i = i + 1) begin b = $random(seed); rx_frame(b, 1 + (i % 3), 1); expect_rx(b, 120 + i); end
        // ---- RX: back-to-back frames without idle gap ----
        rx_frame(8'h12, 0, 1); rx_frame(8'h34, 0, 1); rx_frame(8'h56, 0, 1);
        repeat (CPB) @(negedge clk);
        `CHECK("proto", 130, 3, rx_got_wr - rx_got_rd)
        if (rx_got_wr - rx_got_rd == 3) begin
            `CHECK("func", 131, 8'h12, rx_got_q[rx_got_rd])
            `CHECK("func", 132, 8'h34, rx_got_q[rx_got_rd + 1])
            `CHECK("func", 133, 8'h56, rx_got_q[rx_got_rd + 2])
        end
        rx_got_rd = rx_got_wr;
        // ---- RX: framing error (stop bit = 0) → rx_err, no rx_valid ----
        errs_before = rx_err_count;
        rx_frame(8'h77, 0, 0);
        repeat (CPB) @(negedge clk);
        rx_reg = 1; repeat (CPB) @(negedge clk);
        `CHECK("proto", 140, errs_before + 1, rx_err_count)
        `CHECK("proto", 141, 0, rx_got_wr - rx_got_rd)
        // ---- RX: glitch shorter than half a bit → nothing ----
        errs_before = rx_err_count;
        @(negedge clk); rx_reg = 0; repeat (3) @(negedge clk); rx_reg = 1;
        repeat (12 * CPB) @(negedge clk);
        `CHECK("proto", 150, errs_before, rx_err_count)
        `CHECK("proto", 151, 0, rx_got_wr - rx_got_rd)
        // ---- receiver still alive after error/glitch ----
        rx_frame(8'h9E, 0, 1); expect_rx(8'h9E, 160);

        // ---- loopback: TX → RX ----
        loopback = 1;
        for (i = 0; i < 6; i = i + 1) begin
            b = $random(seed);
            send_byte(b);
            while (tx_busy) @(negedge clk);
            repeat (CPB) @(negedge clk);
            `CHECK("proto", 200 + i, 1, rx_got_wr - rx_got_rd)
            if (rx_got_wr > rx_got_rd) `CHECK("func", 210 + i, b, rx_got_q[rx_got_rd])
            rx_got_rd = rx_got_wr;
        end
        loopback = 0;

        // ---- mid-run reset during a transmission ----
        send_byte(8'h81);
        repeat (3 * CPB) @(negedge clk);
        rst_n = 0; repeat (2) @(negedge clk);
        `CHECK("reset", 300, 1'b1, tx)
        `CHECK("reset", 301, 1'b0, tx_busy)
        rst_n = 1; repeat (2) @(negedge clk);
        tx_exp_rd = tx_exp_wr;  // discard the aborted frame
        send_byte(8'h7E);
        while (tx_busy) @(negedge clk);
        repeat (2 * CPB) @(negedge clk);
        `CHECK("proto", 310, tx_exp_wr, tx_exp_rd)  // last frame fully observed

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
