// Transaction-level scoreboard testbench with protocol assertions
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
    localparam DEPTH = 16;
    reg        clk = 0, rst_n = 0, wr_en = 0, rd_en = 0;
    reg  [7:0] wr_data = 0;
    wire [7:0] rd_data;
    wire       full, empty;
    wire [4:0] count;

    sync_fifo dut (.clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_data(wr_data), .rd_en(rd_en),
                   .rd_data(rd_data), .full(full), .empty(empty), .count(count));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, cyc = 0, seed = `SEED, i;

    // ---- reference model: circular queue driven by the *inputs* only ----
    reg [7:0] q [0:DEPTH-1];
    integer   q_head = 0, q_tail = 0, q_count = 0;
    reg       exp_rd_valid = 0;   // a read was accepted at the last edge
    reg [7:0] exp_rd_data = 0;
    integer   n_writes = 0, n_reads = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            q_head <= 0; q_tail <= 0; q_count <= 0; exp_rd_valid <= 0;
        end else begin
            exp_rd_valid <= 0;
            if (rd_en && q_count > 0) begin
                exp_rd_data  <= q[q_head];
                exp_rd_valid <= 1;
                q_head       <= (q_head + 1) % DEPTH;
                n_reads      <= n_reads + 1;
            end
            if (wr_en && q_count < DEPTH) begin
                q[q_tail] <= wr_data;
                q_tail    <= (q_tail + 1) % DEPTH;
                n_writes  <= n_writes + 1;
            end
            q_count <= q_count + ((wr_en && q_count < DEPTH) ? 1 : 0) - ((rd_en && q_count > 0) ? 1 : 0);
        end
    end

    task step;   // at negedge: compare DUT state with the model, then drive the next inputs
        input integer p_wr, p_rd;  // probabilities in percent
        begin
            cyc = cyc + 1;
            if (!rst_n) begin
                `CHECK("reset", cyc, 5'd0, count)
                `CHECK("reset", cyc, 1'b1, empty)
                `CHECK("reset", cyc, 1'b0, full)
            end else begin
                `CHECK("proto", cyc, q_count[4:0], count)
                `CHECK("proto", cyc, (q_count == 0), empty)
                `CHECK("proto", cyc, (q_count == DEPTH), full)
                if (exp_rd_valid) `CHECK("func", cyc, exp_rd_data, rd_data)
            end
            wr_en   = (($random(seed) & 255) % 100) < p_wr;
            rd_en   = (($random(seed) & 255) % 100) < p_rd;
            wr_data = $random(seed);
        end
    endtask

    initial begin
        // ---- reset with active requests ----
        wr_en = 1; rd_en = 1; wr_data = 8'hA5;
        for (i = 0; i < 3; i = i + 1) begin @(negedge clk); step(100, 100); end
        rst_n = 1;
        // ---- fill only (pushes past full: writes when full must be ignored) ----
        for (i = 0; i < 24; i = i + 1) begin @(negedge clk); step(100, 0); end
        // ---- simultaneous read/write while full ----
        for (i = 0; i < 6;  i = i + 1) begin @(negedge clk); step(100, 100); end
        // ---- drain only (reads past empty must be ignored) ----
        for (i = 0; i < 24; i = i + 1) begin @(negedge clk); step(0, 100); end
        // ---- simultaneous read/write while empty ----
        for (i = 0; i < 6;  i = i + 1) begin @(negedge clk); step(100, 100); end
        // ---- random traffic, write-heavy then read-heavy then balanced ----
        for (i = 0; i < 400; i = i + 1) begin @(negedge clk); step(70, 30); end
        for (i = 0; i < 400; i = i + 1) begin @(negedge clk); step(30, 70); end
        for (i = 0; i < 800; i = i + 1) begin @(negedge clk); step(50, 50); end
        // ---- mid-run reset while half full ----
        rst_n = 0;
        for (i = 0; i < 2; i = i + 1) begin @(negedge clk); step(100, 0); end
        rst_n = 1;
        for (i = 0; i < 200; i = i + 1) begin @(negedge clk); step(60, 40); end
        @(negedge clk); step(0, 0);
        @(negedge clk); step(0, 0);

        if (n_fail == 0) $display("TB_RESULT PASS n_checks=%0d", n_checks);
        else             $display("TB_RESULT FAIL n_fail=%0d n_checks=%0d", n_fail, n_checks);
        $finish;
    end

    initial begin
        #500000;
        $display("TB_FAIL tag=crash case=0 exp=0 got=0");
        $display("TB_RESULT FAIL n_fail=1 n_checks=%0d", n_checks);
        $finish;
    end
endmodule
`undef CHECK
