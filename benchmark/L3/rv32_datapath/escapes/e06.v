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
    
    // Outputs
    reg [31:0] alu_result_reg;
    reg illegal_reg;
    
    // Instruction fields
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire [4:0] rs1_addr = instr[19:15];
    wire [4:0] rs2_addr = instr[24:20];
    wire [4:0] rd_addr = instr[11:7];
    
    // Immediate for I-type
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    
    // Register read (combinational)
    wire [31:0] rs1_val = (rs1_addr == 5'b0) ? 32'b0 : regs[rs1_addr];
    wire [31:0] rs2_val = (rs2_addr == 5'b0) ? 32'b0 : regs[rs2_addr];
    
    // ALU operations
    wire [31:0] result_add = rs1_val + rs2_val;
    wire [31:0] result_sub = rs1_val - rs2_val;
    wire [4:0] shamt_r = rs2_val[4:0];
    wire [4:0] shamt_i = imm_i[4:0];
    wire [31:0] result_sll = rs1_val << shamt_r;
    wire [31:0] result_srl = rs1_val >> shamt_r;
    wire [31:0] result_sra = $signed(rs1_val) >>> shamt_r;
    wire [31:0] result_slt = ($signed(rs1_val) < $signed(rs2_val)) ? 32'h1 : 32'h0;
    wire [31:0] result_sltu = (rs1_val < rs2_val) ? 32'h1 : 32'h0;
    wire [31:0] result_xor = rs1_val ^ rs2_val;
    wire [31:0] result_or = rs1_val | rs2_val;
    wire [31:0] result_and = rs1_val & rs2_val;
    
    // I-type immediate operations
    wire [31:0] result_addi = rs1_val + imm_i;
    wire [31:0] result_slti = ($signed(rs1_val) < $signed(imm_i)) ? 32'h1 : 32'h0;
    wire [31:0] result_sltiu = (rs1_val < imm_i) ? 32'h1 : 32'h0;
    wire [31:0] result_xori = rs1_val ^ imm_i;
    wire [31:0] result_ori = rs1_val | imm_i;
    wire [31:0] result_andi = rs1_val & imm_i;
    wire [31:0] result_slli = rs1_val << shamt_i;
    wire [31:0] result_srli = rs1_val >> shamt_i;
    wire [31:0] result_srai = $signed(rs1_val) >>> shamt_i;
    
    // Decode and execution
    wire is_r_type = (opcode == 7'b0110011);
    wire is_i_type = (opcode == 7'b0010011);
    
    // Check legality for R-type
    wire legal_r_add = is_r_type & (funct3 == 3'b000) & (funct7 == 7'b0000000);
    wire legal_r_sub = is_r_type & (funct3 == 3'b000) & (funct7 == 7'b0100000);
    wire legal_r_sll = is_r_type & (funct3 == 3'b001) & (funct7 == 7'b0000000);
    wire legal_r_slt = is_r_type & (funct3 == 3'b010) & (funct7 == 7'b0000000);
    wire legal_r_sltu = is_r_type & (funct3 == 3'b011) & (funct7 == 7'b0000000);
    wire legal_r_xor = is_r_type & (funct3 == 3'b100) & (funct7 == 7'b0000000);
    wire legal_r_srl = is_r_type & (funct3 == 3'b101) & (funct7 == 7'b0000000);
    wire legal_r_sra = is_r_type & (funct3 == 3'b101) & (funct7 == 7'b0100000);
    wire legal_r_or = is_r_type & (funct3 == 3'b110) & (funct7 == 7'b0000000);
    wire legal_r_and = is_r_type & (funct3 == 3'b111) & (funct7 == 7'b0000000);
    
    // Check legality for I-type
    wire legal_i_addi = is_i_type & (funct3 == 3'b000);
    wire legal_i_slti = is_i_type & (funct3 == 3'b010);
    wire legal_i_sltiu = is_i_type & (funct3 == 3'b011);
    wire legal_i_xori = is_i_type & (funct3 == 3'b100);
    wire legal_i_ori = is_i_type & (funct3 == 3'b110);
    wire legal_i_andi = is_i_type & (funct3 == 3'b111);
    wire legal_i_slli = is_i_type & (funct3 == 3'b001) & (funct7 == 7'b0000000);
    wire legal_i_srli = is_i_type & (funct3 == 3'b101) & (funct7 == 7'b0000000);
    wire legal_i_srai = is_i_type & (funct3 == 3'b101) & (funct7 == 7'b0100000);
    
    wire legal_instr = legal_r_add | legal_r_sub | legal_r_sll | legal_r_slt | 
                       legal_r_sltu | legal_r_xor | legal_r_srl | legal_r_sra | 
                       legal_r_or | legal_r_and | legal_i_addi | legal_i_slti | 
                       legal_i_sltiu | legal_i_xori | legal_i_ori | legal_i_andi | 
                       legal_i_slli | legal_i_srli | legal_i_srai;
    
    // Result selection
    wire [31:0] r_type_result = 
        legal_r_add ? result_add :
        legal_r_sub ? result_sub :
        legal_r_sll ? result_sll :
        legal_r_slt ? result_slt :
        legal_r_sltu ? result_sltu :
        legal_r_xor ? result_xor :
        legal_r_srl ? result_srl :
        legal_r_sra ? result_sra :
        legal_r_or ? result_or :
        legal_r_and ? result_and : 32'h0;
        
    wire [31:0] i_type_result = 
        legal_i_addi ? result_addi :
        legal_i_slti ? result_slti :
        legal_i_sltiu ? result_sltiu :
        legal_i_xori ? result_xori :
        legal_i_ori ? result_ori :
        legal_i_andi ? result_andi :
        legal_i_slli ? (rs1_val << shamt_i) :
        legal_i_srli ? (rs1_val >> shamt_i) :
        legal_i_srai ? ($signed(rs1_val) >>> shamt_i) : 32'h0;
    
    wire [31:0] current_result = is_r_type ? r_type_result : i_type_result;
    
    // Write register
    wire write_enable = valid & legal_instr & (rd_addr != 5'b0);
    wire [31:0] write_data = current_result;
    
    // Sequential logic
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
            alu_result_reg <= 32'b0;
            illegal_reg <= 1'b0;
        end
        else if (valid) begin
            if (legal_instr) begin
                if (write_enable) begin
                    regs[rd_addr] <= write_data;
                end
                alu_result_reg <= current_result;
                illegal_reg <= 1'b0;
            end
            else begin
                alu_result_reg <= 32'b0;
                illegal_reg <= 1'b1;
            end
        end
    end
    
    // Output assignments
    assign alu_result = alu_result_reg;
    assign illegal = illegal_reg;
    assign dbg_data = (dbg_addr == 5'b0) ? 32'b0 : regs[dbg_addr];

endmodule
