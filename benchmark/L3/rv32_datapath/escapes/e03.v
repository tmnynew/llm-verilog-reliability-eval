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

    reg [31:0] regs [0:31];
    reg [31:0] alu_result_r;
    reg        illegal_r;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3  = instr[14:12];
    wire [6:0] funct7  = instr[31:25];

    wire [4:0] rs1     = instr[19:15];
    wire [4:0] rs2     = instr[24:20];
    wire [4:0] rd      = instr[11:7];

    wire is_r = (opcode == 7'b0110011);
    wire is_i = (opcode == 7'b0010011);

    wire [31:0] rs1_data = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    wire [31:0] rs2_data = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [4:0]  shamt = instr[24:20];

    wire [31:0] op_b      = is_r ? rs2_data : imm_i;
    wire [4:0]  shift_amt = is_r ? rs2_data[4:0] : shamt;

    wire [31:0] add_sub  = (funct3 == 3'b000) ? ((funct7 == 7'b0100000) ? (rs1_data - op_b) : (rs1_data + op_b)) : 32'd0;
    wire [31:0] sll      = rs1_data << shift_amt;
    wire        slt      = ($signed(rs1_data) < $signed(is_r ? $signed(rs2_data) : $signed(imm_i)));
    wire        sltu     = (rs1_data < (is_r ? rs2_data : imm_i));
    wire [31:0] xor_res  = rs1_data ^ op_b;
    wire [31:0] srl_sra  = (funct7 == 7'b0100000) ? ($signed(rs1_data) >>> shift_amt) : (rs1_data >> shift_amt);
    wire [31:0] or_res   = rs1_data | op_b;
    wire [31:0] and_res  = rs1_data & op_b;

    reg [31:0] alu_val;
    reg        ill;

    always @(*) begin
        alu_val = 32'd0;
        ill     = 1'b1;

        if (is_r) begin
            case (funct3)
                3'b000: begin
                    if (funct7 == 7'b0000000 || funct7 == 7'b0100000) begin
                        alu_val = add_sub;
                        ill     = 1'b0;
                    end
                end
                3'b001: begin
                    if (funct7 == 7'b0000000) begin
                        alu_val = sll;
                        ill     = 1'b0;
                    end
                end
                3'b010: begin
                    if (funct7 == 7'b0000000) begin
                        alu_val = {31'd0, slt};
                        ill     = 1'b0;
                    end
                end
                3'b011: begin
                    if (funct7 == 7'b0000000) begin
                        alu_val = {31'd0, sltu};
                        ill     = 1'b0;
                    end
                end
                3'b100: begin
                    if (funct7 == 7'b0000000) begin
                        alu_val = xor_res;
                        ill     = 1'b0;
                    end
                end
                3'b101: begin
                    if (funct7 == 7'b0000000 || funct7 == 7'b0100000) begin
                        alu_val = srl_sra;
                        ill     = 1'b0;
                    end
                end
                3'b110: begin
                    if (funct7 == 7'b0000000) begin
                        alu_val = or_res;
                        ill     = 1'b0;
                    end
                end
                3'b111: begin
                    if (funct7 == 7'b0000000) begin
                        alu_val = and_res;
                        ill     = 1'b0;
                    end
                end
            endcase
        end else if (is_i) begin
            case (funct3)
                3'b000: begin
                    alu_val = rs1_data + imm_i;
                    ill     = 1'b0;
                end
                3'b001: begin
                    if (instr[31:25] == 7'b0000000) begin
                        alu_val = sll;
                        ill     = 1'b0;
                    end
                end
                3'b010: begin
                    alu_val = {31'd0, slt};
                    ill     = 1'b0;
                end
                3'b011: begin
                    alu_val = {31'd0, sltu};
                    ill     = 1'b0;
                end
                3'b100: begin
                    alu_val = xor_res;
                    ill     = 1'b0;
                end
                3'b101: begin
                    if (instr[31:25] == 7'b0000000 || instr[31:25] == 7'b0100000) begin
                        alu_val = srl_sra;
                        ill     = 1'b0;
                    end
                end
                3'b110: begin
                    alu_val = or_res;
                    ill     = 1'b0;
                end
                3'b111: begin
                    alu_val = and_res;
                    ill     = 1'b0;
                end
            endcase
        end
    end

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'd0;
            end
            alu_result_r <= 32'd0;
            illegal_r    <= 1'b0;
        end else if (valid) begin
            if (!ill && rd != 5'd0) begin
                regs[rd] <= alu_val;
            end
            alu_result_r <= ill ? 32'd0 : alu_val;
            illegal_r    <= ill;
        end
    end

    assign alu_result = alu_result_r;
    assign illegal    = illegal_r;
    assign dbg_data   = (dbg_addr == 5'd0) ? 32'd0 : regs[dbg_addr];

endmodule
