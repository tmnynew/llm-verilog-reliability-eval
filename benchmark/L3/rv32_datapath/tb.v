// Transaction-level testbench for the RV32I ALU datapath: encoder helpers, reference register file, directed corner cases and random stream - see docs/testbench_protocol.md
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

    integer n_checks = 0, n_fail = 0, seed = `SEED, i, k;
    reg [31:0] rf_m [0:31];

    localparam [6:0] OP_R = 7'b0110011, OP_I = 7'b0010011;
    function [31:0] enc_r;
        input [6:0] f7; input [4:0] rs2, rs1; input [2:0] f3; input [4:0] rd;
        enc_r = {f7, rs2, rs1, f3, rd, OP_R};
    endfunction
    function [31:0] enc_i;
        input [11:0] imm; input [4:0] rs1; input [2:0] f3; input [4:0] rd;
        enc_i = {imm, rs1, f3, rd, OP_I};
    endfunction

    // execute one instruction and compare against the reference model
    task exec;
        input [31:0] ins;
        input integer id;
        reg [6:0] op, f7; reg [2:0] f3; reg [4:0] rd, rs1, rs2;
        reg [31:0] a, b, res; reg bad, sub;
        begin
            op = ins[6:0]; rd = ins[11:7]; f3 = ins[14:12]; rs1 = ins[19:15]; rs2 = ins[24:20]; f7 = ins[31:25];
            a = rf_m[rs1];
            if (op == OP_R) begin
                b = rf_m[rs2]; sub = f7[5];
                bad = !(f7 == 7'b0000000 || (f7 == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101)));
            end else if (op == OP_I) begin
                b = {{20{ins[31]}}, ins[31:20]}; sub = (f3 == 3'b101) && f7[5];
                bad = (f3 == 3'b001 && f7 != 7'b0000000) || (f3 == 3'b101 && f7 != 7'b0000000 && f7 != 7'b0100000);
            end else begin
                b = 0; sub = 0; bad = 1;
            end
            case (f3)
                3'b000: res = sub ? (a - b) : (a + b);
                3'b001: res = a << b[4:0];
                3'b010: res = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
                3'b011: res = (a < b) ? 32'd1 : 32'd0;
                3'b100: res = a ^ b;
                3'b101: res = sub ? $unsigned($signed(a) >>> b[4:0]) : (a >> b[4:0]);
                3'b110: res = a | b;
                default: res = a & b;
            endcase
            if (bad) res = 0;
            @(negedge clk); instr = ins; valid = 1;
            @(negedge clk); valid = 0; instr = ~ins;
            `CHECK("func", id, bad, illegal)
            `CHECK("func", id, res, alu_result)
            if (!bad && rd != 0) rf_m[rd] = res;
            dbg_addr = rd; #1;
            `CHECK("func", id, rf_m[rd], dbg_data)
        end
    endtask

    task scan_all;                        // compare the whole register file through the debug port
        input integer id;
        begin
            for (k = 0; k < 32; k = k + 1) begin
                dbg_addr = k; #1;
                `CHECK("func", id + k, rf_m[k], dbg_data)
            end
        end
    endtask

    reg [31:0] ins, hold_r; reg hold_i;
    reg [6:0] f7; reg [4:0] rs1, rs2, rd; reg [2:0] f3; reg [11:0] imm;
    initial begin
        for (k = 0; k < 32; k = k + 1) rf_m[k] = 0;
        rst_n = 0; valid = 1; instr = enc_i(12'd7, 5'd0, 3'b000, 5'd9);   // must be ignored during reset
        repeat (3) @(negedge clk);
        `CHECK("reset", 1, 32'd0, alu_result)
        `CHECK("reset", 2, 1'b0, illegal)
        valid = 0; rst_n = 1;
        @(negedge clk);
        scan_all(100);

        // directed: build interesting operands, then exercise every operation
        exec(enc_i(12'h7FF, 5'd0, 3'b000, 5'd1), 200);         // x1 = 0x7FF
        exec(enc_i(12'h800, 5'd0, 3'b000, 5'd2), 201);         // x2 = 0xFFFFF800 (sign extension)
        exec(enc_i(12'd20,  5'd1, 3'b001, 5'd3), 202);         // x3 = x1 << 20
        exec(enc_i(12'h7FF, 5'd3, 3'b110, 5'd3), 203);         // x3 |= 0x7FF
        exec(enc_i(12'd11,  5'd3, 3'b001, 5'd4), 204);         // x4 = x3 << 11
        exec(enc_i(12'h7FF, 5'd4, 3'b110, 5'd4), 205);         // x4 = 0x7FFFFFFF
        exec(enc_r(7'b0000000, 5'd1, 5'd4, 3'b000, 5'd5), 206);   // ADD overflow
        exec(enc_r(7'b0100000, 5'd1, 5'd0, 3'b000, 5'd6), 207);   // SUB x6 = -x1
        exec(enc_r(7'b0000000, 5'd1, 5'd6, 3'b010, 5'd7), 208);   // SLT (neg < pos) = 1
        exec(enc_r(7'b0000000, 5'd1, 5'd6, 3'b011, 5'd8), 209);   // SLTU = 0
        exec(enc_r(7'b0000000, 5'd6, 5'd1, 3'b010, 5'd9), 210);   // SLT (pos < neg) = 0
        exec(enc_r(7'b0100000, 5'd1, 5'd6, 3'b101, 5'd10), 211);  // SRA by x1[4:0] = 31
        exec(enc_r(7'b0000000, 5'd1, 5'd6, 3'b101, 5'd11), 212);  // SRL by 31
        exec(enc_r(7'b0000000, 5'd1, 5'd6, 3'b001, 5'd12), 213);  // SLL by 31
        exec(enc_i({7'b0100000, 5'd4}, 5'd2, 3'b101, 5'd13), 214); // SRAI
        exec(enc_i({7'b0000000, 5'd4}, 5'd2, 3'b101, 5'd14), 215); // SRLI
        exec(enc_i({7'b0000000, 5'd0}, 5'd2, 3'b101, 5'd15), 216); // SRLI by 0
        exec(enc_r(7'b0000000, 5'd2, 5'd4, 3'b100, 5'd16), 217);  // XOR
        exec(enc_r(7'b0000000, 5'd2, 5'd4, 3'b110, 5'd17), 218);  // OR
        exec(enc_r(7'b0000000, 5'd2, 5'd4, 3'b111, 5'd18), 219);  // AND
        exec(enc_i(12'h80F, 5'd4, 3'b100, 5'd19), 220);         // XORI negative imm
        exec(enc_i(12'h0F0, 5'd4, 3'b111, 5'd20), 221);         // ANDI
        exec(enc_i(12'h800, 5'd6, 3'b010, 5'd21), 222);         // SLTI
        exec(enc_i(12'h800, 5'd6, 3'b011, 5'd22), 223);         // SLTIU
        exec(enc_i(12'd5, 5'd0, 3'b000, 5'd0), 224);            // write to x0 discarded, alu_result = 5
        exec(enc_r(7'b0000000, 5'd0, 5'd0, 3'b000, 5'd23), 225); // x23 = 0 + 0
        // illegal encodings
        exec(enc_r(7'b0000001, 5'd1, 5'd2, 3'b000, 5'd24), 230); // MUL
        exec(enc_r(7'b0100000, 5'd1, 5'd2, 3'b100, 5'd24), 231); // XOR with funct7 = 0100000
        exec(enc_r(7'b0100000, 5'd1, 5'd2, 3'b001, 5'd24), 232); // SLL with funct7 = 0100000
        exec(enc_i({7'b0100000, 5'd3}, 5'd1, 3'b001, 5'd24), 233); // SLLI bad imm[11:5]
        exec(enc_i({7'b0000001, 5'd3}, 5'd1, 3'b101, 5'd24), 234); // SRLI bad imm[11:5]
        exec({12'd0, 5'd1, 3'b010, 5'd24, 7'b0000011}, 235);     // LW
        exec({20'd1, 5'd24, 7'b0110111}, 236);                   // LUI
        exec({12'd0, 5'd1, 3'b000, 5'd24, 7'b1100011}, 237);     // BEQ
        exec(32'h0000_0000, 238);
        exec(32'hFFFF_FFFF, 239);
        exec(enc_i(12'd5, 5'd0, 3'b000, 5'd0), 240);             // still alive
        // valid = 0: outputs and register file hold
        hold_r = alu_result; hold_i = illegal;
        @(negedge clk); instr = enc_i(12'd99, 5'd0, 3'b000, 5'd25); valid = 0;
        @(negedge clk); instr = enc_r(7'b0000001, 5'd1, 5'd2, 3'b000, 5'd26);
        @(negedge clk);
        `CHECK("func", 250, hold_r, alu_result)
        `CHECK("func", 251, hold_i, illegal)
        scan_all(300);

        // random instruction stream
        for (i = 0; i < 400; i = i + 1) begin
            k = {$random(seed)} % 100;
            rs1 = $random(seed); rs2 = $random(seed); rd = $random(seed); f3 = $random(seed); imm = $random(seed);
            if (k < 45) begin
                f7 = ((f3 == 3'b000 || f3 == 3'b101) && ($random(seed) & 1)) ? 7'b0100000 : 7'b0000000;
                ins = enc_r(f7, rs2, rs1, f3, rd);
            end else if (k < 90) begin
                if (f3 == 3'b001) imm[11:5] = 7'b0000000;
                if (f3 == 3'b101) imm[11:5] = ($random(seed) & 1) ? 7'b0100000 : 7'b0000000;
                ins = enc_i(imm, rs1, f3, rd);
            end else begin
                case ({$random(seed)} % 4)
                    0: ins = enc_r(7'b0000001, rs2, rs1, f3, rd);
                    1: ins = enc_r(7'b0100000, rs2, rs1, (f3 == 3'b000 || f3 == 3'b101) ? 3'b100 : f3, rd);
                    2: ins = enc_i({7'b0100000, imm[4:0]}, rs1, 3'b001, rd);
                    default: begin ins = $random(seed); ins[6:0] = (ins[7]) ? 7'b0110111 : 7'b0000011; end
                endcase
            end
            exec(ins, 1000 + i);
        end
        scan_all(2000);

        // mid-run reset clears everything
        rst_n = 0; repeat (2) @(negedge clk);
        for (k = 0; k < 32; k = k + 1) rf_m[k] = 0;
        `CHECK("reset", 2100, 32'd0, alu_result)
        `CHECK("reset", 2101, 1'b0, illegal)
        rst_n = 1; @(negedge clk);
        scan_all(2200);
        exec(enc_i(12'hABC, 5'd0, 3'b000, 5'd31), 2300);
        exec(enc_r(7'b0000000, 5'd31, 5'd31, 3'b000, 5'd30), 2301);
        scan_all(2400);
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
