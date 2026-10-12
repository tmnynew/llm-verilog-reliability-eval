## 功能
RV32I 整数运算子集的单周期执行单元：指令译码 + 32×32 位寄存器堆 + ALU，没有 PC、存储器与分支。用于验证译码与 ALU 语义。

## 端口
| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | **同步**复位，低电平有效 |
| instr | input | 32 | 指令字 |
| valid | input | 1 | 为 1 的上升沿执行 instr |
| alu_result | output | 32 | 最近一条被执行指令的 ALU 结果（寄存器输出），非法指令时为 0 |
| illegal | output | 1 | 最近一条被执行指令是否非法（寄存器输出） |
| dbg_addr | input | 5 | 调试读地址 |
| dbg_data | output | 32 | 寄存器 x[dbg_addr] 的当前值（组合读口，x0 读出 0） |

## 支持的指令
| 类型 | opcode | funct3 | funct7 / imm[11:5] | 指令 |
|---|---|---|---|---|
| R | 0110011 | 000 | 0000000 / 0100000 | ADD / SUB |
| R | 0110011 | 001 / 010 / 011 | 0000000 | SLL / SLT / SLTU |
| R | 0110011 | 100 / 110 / 111 | 0000000 | XOR / OR / AND |
| R | 0110011 | 101 | 0000000 / 0100000 | SRL / SRA |
| I | 0010011 | 000 / 010 / 011 / 100 / 110 / 111 | 任意（属于立即数） | ADDI / SLTI / SLTIU / XORI / ORI / ANDI |
| I | 0010011 | 001 | 0000000 | SLLI（shamt = imm[4:0]） |
| I | 0010011 | 101 | 0000000 / 0100000 | SRLI / SRAI（shamt = imm[4:0]） |

R 型移位量取 rs2 的低 5 位；I 型立即数为 imm[11:0] 符号扩展到 32 位。SLT/SLTI 为有符号比较，SLTU/SLTIU 为无符号比较，结果为 0 或 1。其他 opcode，或 funct7 不在上表中的组合（例如 R 型 funct7 = 0000001、SLLI 的 imm[11:5] ≠ 0、SRLI/SRAI 的 imm[11:5] 不为 0000000/0100000、SUB/SRA 之外的 R 型指令使用 funct7 = 0100000），均为非法。

## 行为（均以时钟上升沿为准）
1. 复位：所有 32 个寄存器清零，`alu_result = 0`，`illegal = 0`。
2. `valid = 1` 的上升沿：译码 instr，读取 rs1、rs2（x0 恒读 0），计算结果。合法指令：结果写入 rd（rd = x0 时丢弃），`alu_result` 更新为结果、`illegal = 0`；非法指令：不写寄存器，`alu_result = 0`、`illegal = 1`。两个输出均在该上升沿之后的周期有效并保持。
3. `valid = 0` 的上升沿：寄存器堆与两个输出均保持不变。
4. `dbg_data` 组合地反映寄存器当前值：某条指令在上升沿写入 rd 后，下一个周期 `dbg_data`（dbg_addr = rd）即为新值。

## 时序示例
| 周期 | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| instr | ADDI x1, x0, 5 | ADD x2, x1, x1 | MUL x3, x1, x1（非法） | – |
| valid | 1 | 1 | 1 | 0 |
| alu_result（周期内稳定值） | – | 5 | 10 | 0 |
| illegal | – | 0 | 0 | 1 |
| dbg_data（dbg_addr = 1 / 2 / 3） | – | 5 | 10 | 0 |
