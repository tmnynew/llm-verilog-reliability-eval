// Weak testbench (Exp. 2 baseline): "fill it, then drain it" smoke test - after 16 writes full/empty/count must
// say full, after 16 reads they must say empty, and only the FIRST word read back is spot-checked. The remaining
// 15 data words are never compared; no data with the MSB set, no write when full / read when empty, no
// simultaneous read+write, no random traffic, no mid-run reset. Students add directed stimulus / assertions
// until the mutation score reaches >= 90 % and the escaped samples in escapes/ are detected
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

module tb_sync_fifo;
    reg        clk = 0, rst_n = 0, wr_en = 0, rd_en = 0;
    reg  [7:0] wr_data = 0;
    wire [7:0] rd_data;
    wire       full, empty;
    wire [4:0] count;

    sync_fifo dut (.clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_data(wr_data), .rd_en(rd_en),
                   .rd_data(rd_data), .full(full), .empty(empty), .count(count));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, i;

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        `CHECK("reset", 0, 1'b1, empty)
        `CHECK("reset", 0, 5'd0, count)
        // fill: 16 writes
        for (i = 1; i <= 16; i = i + 1) begin
            wr_en = 1; wr_data = i[7:0];
            @(negedge clk);
        end
        wr_en = 0;
        @(negedge clk);
        `CHECK("proto", 1, 1'b1, full)
        `CHECK("proto", 1, 1'b0, empty)
        `CHECK("proto", 1, 5'd16, count)
        // drain: 16 reads, spot-check the first word (rd_data is registered: valid one cycle later)
        for (i = 1; i <= 16; i = i + 1) begin
            rd_en = 1;
            @(negedge clk);
            if (i == 1) `CHECK("func", 1, 8'd1, rd_data)
        end
        rd_en = 0;
        @(negedge clk);
        `CHECK("proto", 2, 1'b0, full)
        `CHECK("proto", 2, 1'b1, empty)
        `CHECK("proto", 2, 5'd0, count)

        if (n_fail == 0) $display("TB_RESULT PASS n_checks=%0d", n_checks);
        else             $display("TB_RESULT FAIL n_fail=%0d n_checks=%0d", n_fail, n_checks);
        $finish;
    end

    initial begin
        #100000;
        $display("TB_FAIL tag=crash case=0 exp=0 got=0");
        $display("TB_RESULT FAIL n_fail=1 n_checks=%0d", n_checks);
        $finish;
    end
endmodule
`undef CHECK
