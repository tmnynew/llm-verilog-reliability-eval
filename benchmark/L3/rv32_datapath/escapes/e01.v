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

    // 寄存器堆
    reg [31:0] regs [0:31];
    integer i;

    // 输出寄存器
    reg [31:0] alu_result_reg;
    reg illegal_reg;

    assign alu_result = alu_result_reg;
    assign illegal = illegal_reg;

    // 组合读口
    assign dbg_data = (dbg_addr == 5'd0) ? 32'd0 : regs[dbg_addr];

    // 指令字段
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];
    wire [6:0] funct7 = instr[31:25];
    wire [11:0] imm   = instr[31:20];

    // 立即数符号扩展
    wire [31:0] imm_sext = {{20{imm[11]}}, imm};

    // 读寄存器
    wire [31:0] rs1_data = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    wire [31:0] rs2_data = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

    // 移位量
    wire [4:0] shamt_r = rs2_data[4:0];
    wire [4:0] shamt_i = imm[4:0];

    // 非法检测
    reg illegal_comb;
    always @* begin
        illegal_comb = 1'b0;
        case (opcode)
            7'b0110011: begin // R-type
                case (funct3)
                    3'b000: begin // ADD/SUB
                        if (funct7 != 7'b0000000 && funct7 != 7'b0100000)
                            illegal_comb = 1'b1;
                    end
                    3'b001, 3'b010, 3'b011,
                    3'b100, 3'b110, 3'b111: begin
                        if (funct7 != 7'b0000000)
                            illegal_comb = 1'b1;
                    end
                    3'b101: begin // SRL/SRA
                        if (funct7 != 7'b0000000 && funct7 != 7'b0100000)
                            illegal_comb = 1'b1;
                    end
                    default: illegal_comb = 1'b1;
                endcase
            end
            7'b0010011: begin // I-type
                case (funct3)
                    3'b000, 3'b010, 3'b011,
                    3'b100, 3'b110, 3'b111: begin
                        // 任意立即数均合法
                    end
                    3'b001: begin // SLLI
                        if (imm[11:5] != 7'b0000000)
                            illegal_comb = 1'b1;
                    end
                    3'b101: begin // SRLI/SRAI
                        if (imm[11:5] != 7'b0000000 && imm[11:5] != 7'b0100000)
                            illegal_comb = 1'b1;
                    end
                    default: illegal_comb = 1'b1;
                endcase
            end
            default: illegal_comb = 1'b1;
        endcase
    end

    // ALU 计算
    reg [31:0] alu_comb;
    always @* begin
        alu_comb = 32'd0;
        if (!illegal_comb) begin
            case (opcode)
                7'b0110011: begin
                    case (funct3)
                        3'b000: alu_comb = (funct7 == 7'b0100000) ? (rs1_data - rs2_data) : (rs1_data + rs2_data);
                        3'b001: alu_comb = rs1_data << shamt_r;
                        3'b010: alu_comb = ($signed(rs1_data) < $signed(rs2_data)) ? 32'd1 : 32'd0;
                        3'b011: alu_comb = (rs1_data < rs2_data) ? 32'd1 : 32'd0;
                        3'b100: alu_comb = rs1_data ^ rs2_data;
                        3'b101: alu_comb = (funct7 == 7'b0100000) ? ($signed(rs1_data) >>> shamt_r) : (rs1_data >> shamt_r);
                        3'b110: alu_comb = rs1_data | rs2_data;
                        3'b111: alu_comb = rs1_data & rs2_data;
                        default: alu_comb = 32'd0;
                    endcase
                end
                7'b0010011: begin
                    case (funct3)
                        3'b000: alu_comb = rs1_data + imm_sext;
                        3'b001: alu_comb = rs1_data << shamt_i;
                        3'b010: alu_comb = ($signed(rs1_data) < $signed(imm_sext)) ? 32'd1 : 32'd0;
                        3'b011: alu_comb = (rs1_data < imm_sext) ? 32'd1 : 32'd0;
                        3'b100: alu_comb = rs1_data ^ imm_sext;
                        3'b101: alu_comb = (imm[11:5] == 7'b0100000) ? ($signed(rs1_data) >>> shamt_i) : (rs1_data >> shamt_i);
                        3'b110: alu_comb = rs1_data | imm_sext;
                        3'b111: alu_comb = rs1_data & imm_sext;
                        default: alu_comb = 32'd0;
                    endcase
                end
                default: alu_comb = 32'd0;
            endcase
        end
    end

    // 时序逻辑
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
            alu_result_reg <= 32'd0;
            illegal_reg <= 1'b0;
        end else if (valid) begin
            if (!illegal_comb) begin
                if (rd != 5'd0)
                    regs[rd] <= alu_comb;
                alu_result_reg <= alu_comb;
                illegal_reg <= 1'b0;
            end else begin
                alu_result_reg <= 32'd0;
                illegal_reg <= 1'b1;
            end
        end
    end

endmodule
