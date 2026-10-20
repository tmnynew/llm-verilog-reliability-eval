## 功能
面向 256 字节单端口同步存储器的字节复制 DMA。一次任务把 `len` 个字节从 `src` 复制到 `dst`，对 i = 0…len−1 依次执行"读 (src+i) → 写 (dst+i)"，所有地址按 256 取模。由于严格逐字节先读后写，源区与目标区重叠时的结果由该顺序唯一确定（等价于软件中的 `for (i=0;i<len;i++) mem[dst+i] = mem[src+i];`）。

## 端口
| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | **同步**复位，低电平有效 |
| start | input | 1 | 启动，仅在 busy = 0 时被接受 |
| src / dst / len | input | 8 | 源地址、目标地址、字节数，在 start 被接受的上升沿采样 |
| busy | output | 1 | 任务进行中 |
| done | output | 1 | 任务完成脉冲，持续 1 个周期 |
| mem_addr | output | 8 | 存储器地址 |
| mem_wdata | output | 8 | 写数据 |
| mem_we | output | 1 | 写使能：上升沿把 mem_wdata 写入 mem_addr |
| mem_re | output | 1 | 读使能：上升沿发起读，**下一个周期** mem_rdata 为 mem_addr 处的数据（同步读，1 周期延迟） |
| mem_rdata | input | 8 | 读数据 |

## 行为（均以时钟上升沿为准）
1. 复位：`busy = 0`，`done = 0`，`mem_we = mem_re = 0`。
2. 接受 start：`busy = 0` 且 `start = 1` 的上升沿采样 src、dst、len；之后 `busy = 1` 直至任务结束，期间 start 被忽略。
3. 复制：对每个 i，先在某个上升沿置 `mem_re = 1`、`mem_addr = src + i`，再在其后的上升沿置 `mem_we = 1`、`mem_addr = dst + i`、`mem_wdata` 为读到的字节。整个任务恰好产生 len 次读与 len 次写，读地址全部落在源区、写地址全部落在目标区，且第 i 次写必须发生在第 i 次读之后。
4. 结束：最后一次写之后，`done` 输出 1 个周期的脉冲，`busy` 在 done 为 1 的周期或其下一个周期回到 0。任务总时长（start 被接受到 done）不超过 4·len + 8 个周期。
5. len = 0：不访问存储器，busy 可以保持 0，done 在 start 被接受后 3 个周期内出现。
6. 任务中复位：立即停止访问（mem_we = mem_re = 0），busy = 0，不产生 done。

## 时序示例（src = 10，dst = 20，len = 2）
| 周期 | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| start | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| busy | 0 | 1 | 1 | 1 | 1 | 0 | 0 |
| mem_re / mem_addr | 0 | 1 / 10 | 0 | 1 / 11 | 0 | 0 | 0 |
| mem_rdata | – | – | M[10] | – | M[11] | – | – |
| mem_we / mem_addr | 0 | 0 | 1 / 20 | 0 | 1 / 21 | 0 | 0 |
| done | 0 | 0 | 0 | 0 | 0 | 1 | 0 |

周期 1 为 start 被接受后的第一个周期。这只是满足要求的一种最简时序，允许更快或更慢（不超过时长上限）的实现。
