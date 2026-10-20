## 功能
AXI4-Lite 从机，8 位字节地址空间，只实现 4 个 32 位寄存器：

| 偏移 | 名称 | 访问 | 复位值 |
|---|---|---|---|
| 0x00 / 0x04 / 0x08 | REG0 / REG1 / REG2 | 读写 | 0x0000_0000 |
| 0x0C | ID | 只读 | 0x5A5A_0003 |

地址位 [1:0] 忽略（按字对齐），[3:2] 选择寄存器，[7:4] 非零视为未映射。

## 端口（以 clk 为 ACLK，rst_n 为同步低有效复位）
| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | **同步**复位，低电平有效 |
| awvalid / awaddr / awready | in / in / out | 1 / 8 / 1 | 写地址通道 |
| wvalid / wdata / wstrb / wready | in / in / in / out | 1 / 32 / 4 / 1 | 写数据通道，wstrb[k] = 1 表示写入字节 k（bit 8k+7…8k） |
| bvalid / bresp / bready | out / out / in | 1 / 2 / 1 | 写响应通道 |
| arvalid / araddr / arready | in / in / out | 1 / 8 / 1 | 读地址通道 |
| rvalid / rdata / rresp / rready | out / out / out / in | 1 / 32 / 2 / 1 | 读数据通道 |

响应编码：OKAY = 2'b00，SLVERR = 2'b10，DECERR = 2'b11。

## 行为（均以时钟上升沿为准）
1. 复位：`bvalid = 0`，`rvalid = 0`，REG0～REG2 清零。
2. 握手：某通道在 valid = 1 且 ready = 1 的上升沿完成一次传输。从机的 ready 不得依赖于同通道的 valid 之外的主机信号的组合路径以外的方式产生死锁；valid 一旦置 1，在握手前不得撤销、payload 不得改变（bvalid/bresp、rvalid/rdata/rresp 均如此）。bvalid、rvalid 必须为寄存器输出。
3. 写：AW 与 W 可以任意先后到达（可以同一周期），从机可独立接受二者；两者都完成握手后，最迟在其后的 4 个周期内置 `bvalid = 1`：地址映射到 REG0～REG2 时按 wstrb 写入并返回 OKAY；地址为 0x0C 时不写、返回 SLVERR；[7:4] 非零时不写、返回 DECERR。bvalid 在 bready = 1 的上升沿完成握手后撤销。写响应未完成时可以（不强制）拉低 awready/wready。
4. 读：AR 握手后最迟 4 个周期内置 `rvalid = 1`：映射地址返回相应寄存器值（0x0C 返回 ID）与 OKAY；[7:4] 非零时 rdata = 0、rresp = DECERR。rvalid 在 rready = 1 的上升沿握手后撤销。
5. 读写相互独立：一个写事务等待 W 期间，读事务必须仍能完成。
6. wstrb = 0 的写返回 OKAY 且寄存器不变。

## 时序示例（写 REG1，AW 先于 W 一个周期到达，bready 恒为 1）
| 周期 | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| awvalid / awready | 1 / 1 | 0 | 0 | 0 | 0 |
| wvalid / wready | 0 | 1 / 1 | 0 | 0 | 0 |
| bvalid / bresp | 0 | 0 | 0 或 1 | 1 / OKAY（若周期 2 未置 1） | 0 |

AW 在周期 0、W 在周期 1 握手；bvalid 最迟在周期 5 之前出现，bready = 1 时握手后立即撤销。
