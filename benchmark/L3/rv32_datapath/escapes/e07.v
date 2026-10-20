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
    reg [31:0] regfile [0:31];
    integer i;
    
    // ALU signals
    wire [31:0] rs1_data, rs2_data;
    wire [31:0] alu_op1, alu_op2;
    wire [3:0] alu_control;
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;
    wire [4:0] rs1, rs2, rd;
    reg [31:0] alu_result_reg;
    
    // Instruction decode
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    assign rs1 = instr[19:15];
    assign rs2 = instr[24:20];
    assign rd = instr[11:7];
    
    // Register read
    assign rs1_data = (rs1 == 5'b0) ? 32'b0 : regfile[rs1];
    assign rs2_data = (rs2 == 5'b0) ? 32'b0 : regfile[rs2];
    
    // ALU operands
    assign alu_op1 = rs1_data;
    assign alu_op2 = (opcode == 7'b0010011) ? {27'b0, instr[31:20]} : rs2_data; // Immediate for I-type
    
    // ALU control logic
    wire is_r_type = (opcode == 7'b0110011);
    wire is_i_type = (opcode == 7'b0010011);
    
    assign alu_control = 
        (is_r_type && funct3 == 3'b000 && funct7 == 7'b0000000) ? 4'b0000 :  // ADD
        (is_r_type && funct3 == 3'b000 && funct7 == 7'b0100000) ? 4'b0001 :  // SUB
        (is_r_type && funct3 == 3'b001 && funct7 == 7'b0000000) ? 4'b0010 :  // SLL
        (is_r_type && funct3 == 3'b010 && funct7 == 7'b0000000) ? 4'b0011 :  // SLT
        (is_r_type && funct3 == 3'b011 && funct7 == 7'b0000000) ? 4'b0100 :  // SLTU
        (is_r_type && funct3 == 3'b100 && funct7 == 7'b0000000) ? 4'b0101 :  // XOR
        (is_r_type && funct3 == 3'b101 && funct7 == 7'b0000000) ? 4'b0110 :  // SRL
        (is_r_type && funct3 == 3'b101 && funct7 == 7'b0100000) ? 4'b0111 :  // SRA
        (is_r_type && funct3 == 3'b110 && funct7 == 7'b0000000) ? 4'b1000 :  // OR
        (is_r_type && funct3 == 3'b111 && funct7 == 7'b0000000) ? 4'b1001 :  // AND
        (is_i_type && funct3 == 3'b000) ? 4'b0000 :  // ADDI
        (is_i_type && funct3 == 3'b010) ? 4'b0011 :  // SLTI
        (is_i_type && funct3 == 3'b011) ? 4'b0100 :  // SLTIU
        (is_i_type && funct3 == 3'b100) ? 4'b0101 :  // XORI
        (is_i_type && funct3 == 3'b110) ? 4'b1000 :  // ORI
        (is_i_type && funct3 == 3'b111) ? 4'b1001 :  // ANDI
        (is_i_type && funct3 == 3'b001) ? 4'b0010 :  // SLLI
        (is_i_type && funct3 == 3'b101 && funct7 == 7'b0000000) ? 4'b0110 :  // SRLI
        (is_i_type && funct3 == 3'b101 && funct7 == 7'b0100000) ? 4'b0111 :  // SRAI
        4'b1111; // Invalid
        
    // ALU
    wire [31:0] alu_out;
    wire [32:0] sub_result, slt_result_signed, slt_result_unsigned;
    
    assign sub_result = {1'b0, alu_op1} - {1'b0, alu_op2};
    assign slt_result_signed = $signed({1'b0, alu_op1}) < $signed({1'b0, alu_op2});
    assign slt_result_unsigned = alu_op1 < alu_op2;
    
    assign alu_out = 
        (alu_control == 4'b0000) ? (alu_op1 + alu_op2) :  // ADD
        (alu_control == 4'b0001) ? sub_result[31:0] :      // SUB
        (alu_control == 4'b0010) ? (alu_op1 << alu_op2[4:0]) :  // SLL
        (alu_control == 4'b0011) ? {31'b0, slt_result_signed[0]} :  // SLT
        (alu_control == 4'b0100) ? {31'b0, slt_result_unsigned[0]} : // SLTU
        (alu_control == 4'b0101) ? (alu_op1 ^ alu_op2) :   // XOR
        (alu_control == 4'b0110) ? (alu_op1 >> alu_op2[4:0]) :  // SRL
        (alu_control == 4'b0111) ? ($signed(alu_op1) >>> alu_op2[4:0]) : // SRA
        (alu_control == 4'b1000) ? (alu_op1 | alu_op2) :   // OR
        (alu_control == 4'b1001) ? (alu_op1 & alu_op2) :   // AND
        32'hxxxxxxxx; // Invalid
        
    // Illegal instruction detection
    assign illegal = 
        (valid && ((opcode != 7'b0110011) && (opcode != 7'b0010011))) ||  // Not R-type or I-type
        (valid && (opcode == 7'b0110011) && (funct3 == 3'b001) && (funct7 != 7'b0000000)) ||  // SLL with wrong funct7
        (valid && (opcode == 7'b0110011) && (funct3 == 3'b101) && (funct7 != 7'b0000000) && (funct7 != 7'b0100000)) ||  // SRL/SRA with wrong funct7
        (valid && (opcode == 7'b0110011) && (funct3 == 3'b110) && (funct7 != 7'b0000000)) ||  // OR with wrong funct7
        (valid && (opcode == 7'b0110011) && (funct3 == 3'b111) && (funct7 != 7'b0000000)) ||  // AND with wrong funct7
        (valid && (opcode == 7'b0110011) && (funct3 == 3'b010) && (funct7 != 7'b0000000)) ||  // SLT with wrong funct7
        (valid && (opcode == 7'b0110011) && (funct3 == 3'b011) && (funct7 != 7'b0000000)) ||  // SLTU with wrong funct7
        (valid && (opcode == 7'b0110011) && (funct3 == 3'b100) && (funct7 != 7'b0000000)) ||  // XOR with wrong funct7
        (valid && (opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 != 7'b0000000) && (funct7 != 7'b0100000)); // SRLI/SRAI with wrong funct7

    // Writeback to register file
    wire write_enable = valid && !illegal && (rd != 5'b0);  // Don't write to x0
    reg [4:0] wr_addr_reg;
    reg [31:0] wr_data_reg;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                regfile[i] <= 32'b0;
            end
        end
        else if (write_enable) begin
            regfile[rd] <= alu_out;
        end
    end
    
    // Output result
    always @(posedge clk) begin
        if (!rst_n)
            alu_result_reg <= 32'b0;
        else if (valid)
            alu_result_reg <= alu_out;
    end
    
    assign alu_result = alu_result_reg;
    
    // Debug port
    assign dbg_data = (dbg_addr == 5'b0) ? 32'b0 : regfile[dbg_addr];

endmodule
