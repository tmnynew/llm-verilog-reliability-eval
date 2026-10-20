// Weak testbench (Exp. 2 baseline): six legal instructions with small positive operands (ADDI, ADD, SUB, OR,
// XOR), checking alu_result and illegal = 0, plus one debug-port read. No shifts, no SLT/SLTU, no negative
// immediates, no illegal encodings, no x0 write, no valid = 0 hold, no reset-value check, no random stream
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
module tb_rv32_datapath;
    reg         clk = 0, rst_n = 0, valid = 0;
    reg  [31:0] instr = 0;
    reg  [4:0]  dbg_addr = 0;
    wire [31:0] alu_result, dbg_data;
    wire        illegal;

    rv32_datapath dut (.clk(clk), .rst_n(rst_n), .instr(instr), .valid(valid), .alu_result(alu_result),
                       .illegal(illegal), .dbg_addr(dbg_addr), .dbg_data(dbg_data));
    always #5 clk = ~clk;

    integer n_checks = 0, n_fail = 0, seed = `SEED;

    localparam [6:0] OP_R = 7'b0110011, OP_I = 7'b0010011;
    function [31:0] enc_r;
        input [6:0] f7; input [4:0] rs2, rs1; input [2:0] f3; input [4:0] rd;
        enc_r = {f7, rs2, rs1, f3, rd, OP_R};
    endfunction
    function [31:0] enc_i;
        input [11:0] imm; input [4:0] rs1; input [2:0] f3; input [4:0] rd;
        enc_i = {imm, rs1, f3, rd, OP_I};
    endfunction

    task exec;
        input [31:0] ins;
        input [31:0] exp_res;
        input integer id;
        begin
            @(negedge clk); instr = ins; valid = 1;
            @(negedge clk); valid = 0;
            `CHECK("func", id, 1'b0, illegal)
            `CHECK("func", id + 1, exp_res, alu_result)
        end
    endtask

    initial begin
        rst_n = 0; valid = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        exec(enc_i(12'd5,  5'd0, 3'b000, 5'd1), 32'd5, 10);                 // x1 = 5
        exec(enc_i(12'd7,  5'd0, 3'b000, 5'd2), 32'd7, 20);                 // x2 = 7
        exec(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3), 32'd12, 30);      // x3 = x1 + x2
        exec(enc_r(7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4), 32'd2, 40);       // x4 = x2 - x1
        exec(enc_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd5), 32'd7, 50);       // x5 = x1 | x2
        exec(enc_r(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd6), 32'd2, 60);       // x6 = x1 ^ x2
        dbg_addr = 5'd3; #1;
        `CHECK("func", 70, 32'd12, dbg_data)
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
