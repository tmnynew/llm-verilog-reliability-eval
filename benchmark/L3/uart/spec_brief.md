设计一个 8N1 格式的 UART 收发器：发送端在 tx_start 时把 tx_data 串行发出并给出 tx_busy；接收端从 rx 恢复字节，输出 rx_data 与一个周期的 rx_valid 脉冲，停止位错误时输出 rx_err。每位持续 CLKS_PER_BIT 个时钟周期，同步低有效复位。
