设计一个 SPI 从机 `spi_slave`（模式 0，MSB 先发）：sclk、cs_n、mosi 为异步输入，需在系统时钟 clk 下过采样；cs_n 拉低时装载 tx_data 并逐位输出到 miso，每收到 8 位输出 rx_data 并产生 1 个周期的 rx_valid 脉冲；cs_n 为高时 miso 输出 0。
