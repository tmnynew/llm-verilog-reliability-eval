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

    // 同步器
    reg [1:0] sclk_sync, cs_n_sync, mosi_sync;
    wire sclk_pos_edge, sclk_neg_edge, cs_n_neg_edge;

    always @(posedge clk) begin
        sclk_sync <= {sclk_sync[0], sclk};
        cs_n_sync <= {cs_n_sync[0], cs_n};
        mosi_sync <= {mosi_sync[0], mosi};
    end

    assign sclk_pos_edge = !sclk_sync[1] & sclk_sync[0];
    assign sclk_neg_edge = sclk_sync[1] & !sclk_sync[0];
    assign cs_n_neg_edge = cs_n_sync[1] & !cs_n_sync[0];

    // 内部信号
    reg [7:0] tx_shift_reg, rx_shift_reg;
    reg [2:0] bit_count;
    reg [7:0] rx_data_reg;
    reg rx_valid_reg;
    reg miso_reg;
    reg transfer_active;

    // 主逻辑
    always @(posedge clk) begin
        if (!rst_n) begin
            tx_shift_reg <= 8'h00;
            rx_shift_reg <= 8'h00;
            bit_count <= 3'h0;
            rx_data_reg <= 8'h00;
            rx_valid_reg <= 1'b0;
            miso_reg <= 1'b0;
            transfer_active <= 1'b0;
        end
        else begin
            // 检测片选下降沿
            if (cs_n_neg_edge) begin
                tx_shift_reg <= tx_data;
                bit_count <= 3'h0;
                transfer_active <= 1'b1;
                rx_valid_reg <= 1'b0;
                // 在4个clk内输出最高位
                miso_reg <= tx_data[7];
            end
            // 如果cs_n为高，停止传输
            else if (cs_n_sync[0]) begin
                transfer_active <= 1'b0;
                miso_reg <= 1'b0;
                rx_valid_reg <= 1'b0;
            end
            // 在传输过程中处理SPI时序
            else if (transfer_active) begin
                // sclk上升沿采样mosi（接收）
                if (sclk_pos_edge) begin
                    rx_shift_reg[bit_count] <= mosi_sync[0];
                    bit_count <= bit_count + 1'b1;
                    
                    // 第8位接收完成后
                    if (bit_count == 3'd7) begin
                        rx_data_reg <= {mosi_sync[0], rx_shift_reg[6:0]};
                        rx_valid_reg <= 1'b1;
                        bit_count <= 3'h0; // 准备下一字节
                        // miso输出0（下一字节还未装载）
                        miso_reg <= 1'b0;
                    end
                    else begin
                        // 继续接收下一字节时，输出当前待发送位
                        miso_reg <= tx_shift_reg[6-bit_count];
                    end
                end
                // sclk下降沿切换miso（发送）
                else if (sclk_neg_edge) begin
                    if (bit_count > 0 && bit_count < 8) begin
                        miso_reg <= tx_shift_reg[6-(bit_count-1)];
                    end
                end
                else begin
                    rx_valid_reg <= 1'b0;
                end
            end
            else begin
                rx_valid_reg <= 1'b0;
            end
        end
    end

    assign miso = (cs_n_sync[0]) ? 1'b0 : miso_reg;
    assign rx_data = rx_data_reg;
    assign rx_valid = rx_valid_reg;

endmodule
