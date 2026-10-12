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

    // Register file
    reg [31:0] regs [0:31];
    integer i;

    // Output registers
    reg [31:0] alu_result_reg;
    reg illegal_reg;

    assign alu_result = alu_result_reg;
    assign illegal = illegal_reg;

    // Debug read port (combinational)
    assign dbg_data = (dbg_addr == 5'd0) ? 32'd0 : regs[dbg_addr];

    // Instruction fields
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1 = instr[19:15];
    wire [4:0] rs2 = instr[24:20];
    wire [6:0] funct7 = instr[31:25];
    wire [11:0] imm = instr[31:20];

    // Operands
    wire [31:0] rs1_data = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    wire [31:0] rs2_data = (rs2 == 5'd0) ? 32'd0 : regs[rs2];
    wire [31:0] imm_ext = {{20{imm[11]}}, imm};

    // Decode legality
    wire is_r_type = (opcode == 7'b0110011);
    wire is_i_type = (opcode == 7'b0010011);

    wire r_legal_funct7_000 = (funct7 == 7'b0000000);
    wire r_legal_funct7_010 = (funct7 == 7'b0100000);

    wire r_legal = is_r_type & (
        ((funct3 == 3'b000) & (r_legal_funct7_000 | r_legal_funct7_010)) | // ADD/SUB
        ((funct3 == 3'b001) & r_legal_funct7_000) | // SLL
        ((funct3 == 3'b010) & r_legal_funct7_000) | // SLT
        ((funct3 == 3'b011) & r_legal_funct7_000) | // SLTU
        ((funct3 == 3'b100) & r_legal_funct7_000) | // XOR
        ((funct3 == 3'b101) & (r_legal_funct7_000 | r_legal_funct7_010)) | // SRL/SRA
        ((funct3 == 3'b110) & r_legal_funct7_000) | // OR
        ((funct3 == 3'b111) & r_legal_funct7_000)   // AND
    );

    wire i_legal = is_i_type & (
        ((funct3 == 3'b000) | // ADDI
         (funct3 == 3'b010) | // SLTI
         (funct3 == 3'b011) | // SLTIU
         (funct3 == 3'b100) | // XORI
         (funct3 == 3'b110) | // ORI
         (funct3 == 3'b111)) | // ANDI
        ((funct3 == 3'b001) & (imm[11:5] == 7'b0000000)) | // SLLI
        ((funct3 == 3'b101) & ((imm[11:5] == 7'b0000000) | (imm[11:5] == 7'b0100000))) // SRLI/SRAI
    );

    wire legal = r_legal | i_legal;

    // ALU operation
    reg [31:0] alu_out;
    always @(*) begin
        case (opcode)
            7'b0110011: begin
                case (funct3)
                    3'b000: alu_out = (funct7[5] == 1'b1) ? (rs1_data - rs2_data) : (rs1_data + rs2_data);
                    3'b001: alu_out = rs1_data << rs2_data[4:0];
                    3'b010: alu_out = ($signed(rs1_data) < $signed(rs2_data)) ? 32'd1 : 32'd0;
                    3'b011: alu_out = (rs1_data < rs2_data) ? 32'd1 : 32'd0;
                    3'b100: alu_out = rs1_data ^ rs2_data;
                    3'b101: alu_out = (funct7[5] == 1'b1) ? ($signed(rs1_data) >>> rs2_data[4:0]) : (rs1_data >> rs2_data[4:0]);
                    3'b110: alu_out = rs1_data | rs2_data;
                    3'b111: alu_out = rs1_data & rs2_data;
                    default: alu_out = 32'd0;
                endcase
            end
            7'b0010011: begin
                case (funct3)
                    3'b000: alu_out = rs1_data + imm_ext;
                    3'b001: alu_out = rs1_data << imm[4:0];
                    3'b010: alu_out = ($signed(rs1_data) < $signed(imm_ext)) ? 32'd1 : 32'd0;
                    3'b011: alu_out = (rs1_data < imm_ext) ? 32'd1 : 32'd0;
                    3'b100: alu_out = rs1_data ^ imm_ext;
                    3'b101: alu_out = (imm[11:5] == 7'b0100000) ? ($signed(rs1_data) >>> imm[4:0]) : (rs1_data >> imm[4:0]);
                    3'b110: alu_out = rs1_data | imm_ext;
                    3'b111: alu_out = rs1_data & imm_ext;
                    default: alu_out = 32'd0;
                endcase
            end
            default: alu_out = 32'd0;
        endcase
    end

    // Sequential logic
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
            alu_result_reg <= 32'd0;
            illegal_reg <= 1'b0;
        end else if (valid) begin
            if (legal) begin
                if (rd != 5'd0)
                    regs[rd] <= alu_out;
                alu_result_reg <= alu_out;
                illegal_reg <= 1'b0;
            end else begin
                alu_result_reg <= 32'd0;
                illegal_reg <= 1'b1;
            end
        end
    end

endmodule
