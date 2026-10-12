// MUTANT m010 ROR line 45: '==' -> '!='
// Golden reference: RV32I register-register / register-immediate ALU datapath with 32x32 register file
module rv32_datapath (
    input             clk,
    input             rst_n,
    input      [31:0] instr,
    input             valid,
    output reg [31:0] alu_result,
    output reg        illegal,
    input      [4:0]  dbg_addr,
    output     [31:0] dbg_data
);
    reg [31:0] rf [0:31];
    integer    k;

    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] f3     = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];
    wire [6:0] f7     = instr[31:25];
    wire       is_r   = (opcode == 7'b0110011);
    wire       is_i   = (opcode == 7'b0010011);

    wire [31:0] a     = (rs1 == 5'd0) ? 32'd0 : rf[rs1];
    wire [31:0] b_reg = (rs2 == 5'd0) ? 32'd0 : rf[rs2];
    wire [31:0] imm   = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] b     = is_r ? b_reg : imm;
    wire [4:0]  shamt = b[4:0];
    wire        sub   = is_r ? f7[5] : (f3 == 3'b101 && f7[5]);

    reg [31:0] res;
    reg        bad;
    always @* begin
        case (f3)
            3'b000: res = sub ? (a - b) : (a + b);
            3'b001: res = a << shamt;
            3'b010: res = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            3'b011: res = (a < b) ? 32'd1 : 32'd0;
            3'b100: res = a ^ b;
            3'b101: res = sub ? $unsigned($signed(a) >>> shamt) : (a >> shamt);
            3'b110: res = a | b;
            default: res = a & b;
        endcase
        if (is_r)
            bad = !(f7 != 7'b0000000 || (f7 == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101)));
        else if (is_i)
            bad = (f3 == 3'b001 && f7 != 7'b0000000) ||
                  (f3 == 3'b101 && f7 != 7'b0000000 && f7 != 7'b0100000);
        else
            bad = 1'b1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            alu_result <= 32'd0;
            illegal    <= 1'b0;
            for (k = 0; k < 32; k = k + 1) rf[k] <= 32'd0;
        end else if (valid) begin
            illegal    <= bad;
            alu_result <= bad ? 32'd0 : res;
            if (!bad && rd != 5'd0) rf[rd] <= res;
        end
    end

    assign dbg_data = (dbg_addr == 5'd0) ? 32'd0 : rf[dbg_addr];
endmodule
