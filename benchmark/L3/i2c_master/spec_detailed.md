## 功能
标准模式 I2C 主机，一次事务传输一个字节（写或读），7 位从机地址，不支持时钟拉伸与多主机。开漏总线由外部完成：`scl_o`、`sda_o` 为 1 表示释放（总线由上拉变高），为 0 表示拉低；`sda_i` 为 SDA 总线的实际电平。

## 参数
| 参数 | 默认值 | 说明 |
|---|---|---|
| CLK_DIV | 4 | 四分之一 SCL 周期的时钟数，SCL 周期 = 4·CLK_DIV 个 clk 周期 |

## 端口
| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| clk | input | 1 | 系统时钟 |
| rst_n | input | 1 | **同步**复位，低电平有效 |
| start | input | 1 | 启动事务，仅在 busy = 0 时被接受 |
| rw | input | 1 | 0 = 写，1 = 读；在 start 被接受时采样 |
| addr | input | 7 | 从机地址，在 start 被接受时采样 |
| wdata | input | 8 | 写事务的数据字节，在 start 被接受时采样 |
| rdata | output | 8 | 读事务读到的字节，done 时有效并保持 |
| busy | output | 1 | 事务进行中 |
| done | output | 1 | 事务结束脉冲，持续 1 个周期 |
| ack_err | output | 1 | 本次事务中从机未应答（地址或数据 NACK），done 时有效并保持到下一次 start 被接受 |
| scl_o | output | 1 | SCL 驱动，空闲为 1 |
| sda_o | output | 1 | SDA 驱动，空闲为 1 |
| sda_i | input | 1 | SDA 总线电平 |

## 行为（均以 clk 上升沿为准）
每个 SCL 周期分为 4 个相位，每相位 CLK_DIV 个 clk 周期：相位 0 SCL 为低、更新 SDA；相位 1 SCL 拉高；相位 2 SCL 为高、采样 SDA；相位 3 SCL 拉低。数据位 MSB 先发；SDA 仅在 SCL 为低时改变（START/STOP 除外）。
1. 复位：`scl_o = sda_o = 1`，`busy = done = ack_err = 0`。
2. 接受 start：`busy = 0` 且 `start = 1` 的上升沿采样 rw、addr、wdata，清除 ack_err，`busy = 1`；期间的 start 被忽略。
3. START：SCL 为高时 SDA 由 1 变 0，然后 SCL 拉低。
4. 地址字节：发送 {addr, rw} 共 8 位，然后释放 SDA（sda_o = 1）并在第 9 个 SCL 高电平期间采样 sda_i：0 = ACK，1 = NACK。NACK 时置 `ack_err = 1` 并直接进入 STOP。
5. 写事务：发送 wdata 8 位，再采样第 9 位 ACK；NACK 时置 `ack_err = 1`。然后 STOP。
6. 读事务：释放 SDA，在 8 个 SCL 高电平期间依次采样 sda_i 得到 rdata[7]…rdata[0]，然后主机在第 9 位发送 NACK（sda_o = 1），然后 STOP。
7. STOP：SCL 为低时 SDA 拉低，SCL 拉高，再在 SCL 为高时 SDA 释放为 1。STOP 完成后 `done` 输出 1 个周期脉冲，`busy = 0`，`scl_o = sda_o = 1`。
8. 时序：事务期间 SCL 相邻两个上升沿间隔恒为 4·CLK_DIV 个 clk 周期；一次完整事务（含 START 与 STOP）不超过 100·CLK_DIV 个周期。
9. 事务中复位：立即释放总线（scl_o = sda_o = 1），busy = 0，不产生 done。

## 时序示例（写事务，从机应答；每格为一个 SCL 周期）
| SCL 周期 | START | A6 … A0 | R/W=0 | ACK | D7 … D0 | ACK | STOP |
|---|---|---|---|---|---|---|---|
| sda_o | 1→0（SCL 高） | 地址位 | 0 | 1（释放） | 数据位 | 1（释放） | 0→1（SCL 高） |
| 采样 sda_i | – | – | – | 相位 2 | – | 相位 2 | – |

SCL 上升沿共 8 + 1 + 8 + 1 + 1（STOP）= 19 个；地址 NACK 时为 8 + 1 + 1 = 10 个。
