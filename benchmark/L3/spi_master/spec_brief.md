设计一个 SPI 主机 `spi_master`（模式 0：CPOL=0、CPHA=0，MSB 先发，单从机片选 cs_n 低有效）：start 有效时发送 tx_data 的 8 位并同时接收 8 位到 rx_data，sclk 的半周期为 CLK_DIV 个时钟周期，传输期间 busy=1，结束时 done 输出 1 个周期的脉冲。
