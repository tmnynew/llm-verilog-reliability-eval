module spi_slave (
    input clk,
    input rst_n,
    input sclk,
    input cs_n,
    input mosi,
    output miso,
    input [7:0] tx_data,
    output [7:0] rx_data,
    output rx_valid
);

    // 同步寄存器
    reg sclk_sync1, sclk_sync2;
    reg cs_n_sync1, cs_n_sync2;
    reg mosi_sync1, mosi_sync2;

    // 边沿检测
    reg sclk_prev;
    reg cs_n_prev;

    wire sclk_rise, sclk_fall, cs_n_fall;

    // 移位寄存器
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;

    // 接收数据寄存器
    reg [7:0] rx_data_reg;
    reg rx_valid_reg;

    // miso 输出寄存器
    reg miso_reg;

    // 延迟计数器（用于满足时序要求）
    reg [2:0] delay_cnt;
    reg delay_active;

    assign rx_data = rx_data_reg;
    assign rx_valid = rx_valid_reg;
    assign miso = miso_reg;

    // 同步输入信号
    always @(posedge clk) begin
        if (!rst_n) begin
            sclk_sync1 <= 1'b0;
            sclk_sync2 <= 1'b0;
            cs_n_sync1 <= 1'b1;
            cs_n_sync2 <= 1'b1;
            mosi_sync1 <= 1'b0;
            mosi_sync2 <= 1'b0;
        end else begin
            sclk_sync1 <= sclk;
            sclk_sync2 <= sclk_sync1;
            cs_n_sync1 <= cs_n;
            cs_n_sync2 <= cs_n_sync1;
            mosi_sync1 <= mosi;
            mosi_sync2 <= mosi_sync1;
        end
    end

    // 边沿检测
    always @(posedge clk) begin
        if (!rst_n) begin
            sclk_prev <= 1'b0;
            cs_n_prev <= 1'b1;
        end else begin
            sclk_prev <= sclk_sync2;
            cs_n_prev <= cs_n_sync2;
        end
    end

    assign sclk_rise = (sclk_sync2 == 1'b1) && (sclk_prev == 1'b0);
    assign sclk_fall = (sclk_sync2 == 1'b0) && (sclk_prev == 1'b1);
    assign cs_n_fall = (cs_n_sync2 == 1'b0) && (cs_n_prev == 1'b1);

    // 主状态机
    always @(posedge clk) begin
        if (!rst_n) begin
            shift_reg <= 8'b0;
            bit_cnt <= 3'b0;
            rx_data_reg <= 8'b0;
            rx_valid_reg <= 1'b0;
            miso_reg <= 1'b0;
            delay_cnt <= 3'b0;
            delay_active <= 1'b0;
        end else begin
            // 默认值
            rx_valid_reg <= 1'b0;

            if (cs_n_sync2 == 1'b1) begin
                // 片选为高：miso 输出 0，忽略 sclk
                miso_reg <= 1'b0;
                bit_cnt <= 3'b0;
                delay_active <= 1'b0;
                delay_cnt <= 3'b0;
            end else begin
                // 片选为低
                if (cs_n_fall) begin
                    // cs_n 下降沿：装载 tx_data，位计数清零
                    shift_reg <= tx_data;
                    bit_cnt <= 3'b0;
                    delay_active <= 1'b1;
                    delay_cnt <= 3'b0;
                    miso_reg <= tx_data[7];
                end else if (delay_active) begin
                    // 延迟计数
                    if (delay_cnt < 3'b011) begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end else begin
                        delay_active <= 1'b0;
                        delay_cnt <= 3'b0;
                    end
                end else begin
                    // 正常操作
                    if (sclk_rise) begin
                        // 采样 mosi
                        shift_reg <= {shift_reg[6:0], mosi_sync2};
                        if (bit_cnt == 3'b111) begin
                            // 第 8 个上升沿
                            rx_data_reg <= {shift_reg[6:0], mosi_sync2};
                            rx_valid_reg <= 1'b1;
                            bit_cnt <= 3'b0;
                            miso_reg <= 1'b0;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end

                    if (sclk_fall) begin
                        // sclk 下降沿：切换 miso
                        if (bit_cnt < 3'b111) begin
                            miso_reg <= shift_reg[6];
                        end else begin
                            miso_reg <= 1'b0;
                        end
                    end
                end
            end
        end
    end

endmodule
