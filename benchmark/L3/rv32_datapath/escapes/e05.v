module rv32_datapath (
    input clk,
    input rst_n,
    input [31:0] instr,
    input valid,
    output [31:0] alu_result,
    output illegal,
    input [4:0] dbg_addr,
    output [31:0] dbg_data
);

reg [31:0] regfile [0:31];
reg [31:0] alu_out;
reg ilgl;

wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;
wire [4:0] rd, rs1, rs2;
wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
wire [4:0] shamt;

wire [31:0] src1, src2;
wire [31:0] alu_in1, alu_in2;
wire [31:0] result;

// Decode
assign opcode = instr[6:0];
assign funct3 = instr[14:12];
assign funct7 = instr[31:25];
assign rd = instr[11:7];
assign rs1 = instr[19:15];
assign rs2 = instr[24:20];

assign imm_i = { {20{instr[31]}}, instr[31:20] };
assign imm_s = { {20{instr[31]}}, instr[31:25], instr[11:7] };
assign imm_b = { {19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0 };
assign imm_u = { instr[31:12], 12'd0 };
assign imm_j = { {12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0 };

assign shamt = instr[24:20];

// Read registers
assign src1 = (rs1 == 5'd0) ? 32'd0 : regfile[rs1];
assign src2 = (rs2 == 5'd0) ? 32'd0 : regfile[rs2];

// ALU inputs
assign alu_in1 = src1;
assign alu_in2 = (opcode == 7'b110011) ? src2 : imm_i;

// ALU operation selection
wire add_op, sub_op, sll_op, slt_op, sltu_op, xor_op, or_op, and_op, srl_op, sra_op;
wire addi_op, slti_op, sltiu_op, xori_op, ori_op, andi_op, slli_op, srli_op, srai_op;

assign add_op   = (opcode == 7'b110011) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
assign sub_op   = (opcode == 7'b110011) && (funct3 == 3'b000) && (funct7 == 7'b0100000);
assign sll_op   = (opcode == 7'b110011) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
assign slt_op   = (opcode == 7'b110011) && (funct3 == 3'b010) && (funct7 == 7'b0000000);
assign sltu_op  = (opcode == 7'b110011) && (funct3 == 3'b011) && (funct7 == 7'b0000000);
assign xor_op   = (opcode == 7'b110011) && (funct3 == 3'b100) && (funct7 == 7'b0000000);
assign or_op    = (opcode == 7'b110011) && (funct3 == 3'b110) && (funct7 == 7'b0000000);
assign and_op   = (opcode == 7'b110011) && (funct3 == 3'b111) && (funct7 == 7'b0000000);
assign srl_op   = (opcode == 7'b110011) && (funct3 == 3'b101) && (funct7 == 7'b0000000);
assign sra_op   = (opcode == 7'b110011) && (funct3 == 3'b101) && (funct7 == 7'b0100000);

assign addi_op  = (opcode == 7'b0010011) && (funct3 == 3'b000);
assign slti_op  = (opcode == 7'b0010011) && (funct3 == 3'b010);
assign sltiu_op = (opcode == 7'b0010011) && (funct3 == 3'b011);
assign xori_op  = (opcode == 7'b0010011) && (funct3 == 3'b100);
assign ori_op   = (opcode == 7'b0010011) && (funct3 == 3'b110);
assign andi_op  = (opcode == 7'b0010011) && (funct3 == 3'b111);
assign slli_op  = (opcode == 7'b0010011) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
assign srli_op  = (opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 == 7'b0000000);
assign srai_op  = (opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 == 7'b0100000);

// ALU logic
assign result = 
    (add_op) ? (alu_in1 + alu_in2) :
    (sub_op) ? (alu_in1 - alu_in2) :
    (sll_op) ? (alu_in1 << shamt) :
    (slt_op) ? ($signed(alu_in1) < $signed(alu_in2) ? 32'h1 : 32'h0) :
    (sltu_op) ? (alu_in1 < alu_in2 ? 32'h1 : 32'h0) :
    (xor_op) ? (alu_in1 ^ alu_in2) :
    (or_op) ? (alu_in1 | alu_in2) :
    (and_op) ? (alu_in1 & alu_in2) :
    (srl_op) ? (alu_in1 >> shamt) :
    (sra_op) ? ($signed(alu_in1) >>> shamt) :
    (addi_op) ? (alu_in1 + alu_in2) :
    (slti_op) ? ($signed(alu_in1) < $signed(alu_in2) ? 32'h1 : 32'h0) :
    (sltiu_op) ? (alu_in1 < alu_in2 ? 32'h1 : 32'h0) :
    (xori_op) ? (alu_in1 ^ alu_in2) :
    (ori_op) ? (alu_in1 | alu_in2) :
    (andi_op) ? (alu_in1 & alu_in2) :
    (slli_op) ? (alu_in1 << shamt) :
    (srli_op) ? (alu_in1 >> shamt) :
    (srai_op) ? ($signed(alu_in1) >>> shamt) :
    32'h0;

// Illegal instruction check
wire illegal_insn =
    ((opcode == 7'b110011) && (funct3 != 3'b000) && (funct3 != 3'b001) && (funct3 != 3'b010) &&
     (funct3 != 3'b011) && (funct3 != 3'b100) && (funct3 != 3'b110) && (funct3 != 3'b111) && (funct3 != 3'b101)) ||
    ((opcode == 7'b110011) && (funct3 == 3'b101) && (funct7 != 7'b0000000) && (funct7 != 7'b0100000)) ||
    ((opcode == 7'b0010011) && (funct3 == 3'b001) && (funct7 != 7'b0000000)) ||
    ((opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 != 7'b0000000) && (funct7 != 7'b0100000)) ||
    ((opcode == 7'b110011) && (funct3 == 3'b000) && (funct7 != 7'b0000000) && (funct7 != 7'b0100000)) ||
    ((opcode == 7'b110011) && (funct3 == 3'b101) && (funct7 != 7'b0000000) && (funct7 != 7'b0100000));

// Register write logic
reg [31:0] next_alu_result;
reg next_illegal;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (integer i = 0; i < 32; i = i + 1)
            regfile[i] <= 32'd0;
        next_alu_result <= 32'd0;
        next_illegal <= 1'b0;
    end else if (valid) begin
        // Write to register file
        if (rd != 5'd0) begin
            regfile[rd] <= result;
        end

        // Update outputs
        next_alu_result <= result;
        next_illegal <= illegal_insn || (opcode != 7'b110011 && opcode != 7'b0010011);
    end
end

assign alu_result = next_alu_result;
assign illegal = next_illegal;

// Debug read port
assign dbg_data = (dbg_addr == 5'd0) ? 32'd0 : regfile[dbg_addr];

endmodule
