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

    // 移位寄存器
    reg [7:0] shift_reg;
    reg [2:0] bit_count;

    // 输出寄存器
    reg miso_reg;
    reg [7:0] rx_data_reg;
    reg rx_valid_reg;

    // 延迟计数器
    reg [2:0] delay_count;
    reg delay_active;

    // 状态标志
    reg cs_active;

    assign miso = miso_reg;
    assign rx_data = rx_data_reg;
    assign rx_valid = rx_valid_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            sclk_sync1 <= 1'b0;
            sclk_sync2 <= 1'b0;
            cs_n_sync1 <= 1'b1;
            cs_n_sync2 <= 1'b1;
            mosi_sync1 <= 1'b0;
            mosi_sync2 <= 1'b0;
            sclk_prev <= 1'b0;
            cs_n_prev <= 1'b1;
            shift_reg <= 8'b0;
            bit_count <= 3'b0;
            miso_reg <= 1'b0;
            rx_data_reg <= 8'b0;
            rx_valid_reg <= 1'b0;
            delay_count <= 3'b0;
            delay_active <= 1'b0;
            cs_active <= 1'b0;
        end else begin
            // 同步输入
            sclk_sync1 <= sclk;
            sclk_sync2 <= sclk_sync1;
            cs_n_sync1 <= cs_n;
            cs_n_sync2 <= cs_n_sync1;
            mosi_sync1 <= mosi;
            mosi_sync2 <= mosi_sync1;

            // 边沿检测
            sclk_prev <= sclk_sync2;
            cs_n_prev <= cs_n_sync2;

            // 默认值
            rx_valid_reg <= 1'b0;

            // 片选下降沿检测
            if (cs_n_prev == 1'b1 && cs_n_sync2 == 1'b0) begin
                // 装载 tx_data
                shift_reg <= tx_data;
                bit_count <= 3'b0;
                cs_active <= 1'b1;
                delay_count <= 3'b0;
                delay_active <= 1'b1;
                miso_reg <= tx_data[7];
            end

            // 片选上升沿检测
            if (cs_n_prev == 1'b0 && cs_n_sync2 == 1'b1) begin
                cs_active <= 1'b0;
                miso_reg <= 1'b0;
                bit_count <= 3'b0;
                delay_active <= 1'b0;
            end

            // 延迟计数器
            if (delay_active) begin
                if (delay_count < 3'b011) begin
                    delay_count <= delay_count + 1'b1;
                end else begin
                    delay_active <= 1'b0;
                end
            end

            // sclk 上升沿检测（接收数据）
            if (cs_active && sclk_prev == 1'b0 && sclk_sync2 == 1'b1) begin
                shift_reg <= {shift_reg[6:0], mosi_sync2};
                bit_count <= bit_count + 1'b1;
                
                if (bit_count == 3'b111) begin
                    // 第8个上升沿
                    rx_data_reg <= {shift_reg[6:0], mosi_sync2};
                    rx_valid_reg <= 1'b1;
                    bit_count <= 3'b0;
                end
            end

            // sclk 下降沿检测（发送数据）
            if (cs_active && sclk_prev == 1'b1 && sclk_sync2 == 1'b0) begin
                if (bit_count < 3'b111) begin
                    miso_reg <= shift_reg[6];
                end else begin
                    miso_reg <= 1'b0;
                end
            end

            // 延迟后更新 miso（下降沿后4个clk内）
            if (delay_active && delay_count == 3'b011) begin
                if (cs_active && sclk_sync2 == 1'b0) begin
                    if (bit_count < 3'b111) begin
                        miso_reg <= shift_reg[6];
                    end else begin
                        miso_reg <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
