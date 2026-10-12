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

    // 同步寄存器（2级）
    reg sclk_sync1, sclk_sync2;
    reg cs_n_sync1, cs_n_sync2;
    reg mosi_sync1, mosi_sync2;

    // 边沿检测
    reg sclk_sync2_d;
    reg cs_n_sync2_d;

    wire sclk_pos = sclk_sync2 & ~sclk_sync2_d;
    wire sclk_neg = ~sclk_sync2 & sclk_sync2_d;
    wire cs_n_pos = cs_n_sync2 & ~cs_n_sync2_d;
    wire cs_n_neg = ~cs_n_sync2 & cs_n_sync2_d;

    // 移位寄存器与计数
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [3:0] bit_cnt;
    reg [7:0] rx_data_reg;
    reg rx_valid_reg;
    reg miso_reg;

    assign rx_data  = rx_data_reg;
    assign rx_valid = rx_valid_reg;
    assign miso     = miso_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            sclk_sync1   <= 1'b0;
            sclk_sync2   <= 1'b0;
            sclk_sync2_d <= 1'b0;
            cs_n_sync1   <= 1'b1;
            cs_n_sync2   <= 1'b1;
            cs_n_sync2_d <= 1'b1;
            mosi_sync1   <= 1'b0;
            mosi_sync2   <= 1'b0;
            tx_shift     <= 8'b0;
            rx_shift     <= 8'b0;
            bit_cnt      <= 4'b0;
            rx_data_reg  <= 8'b0;
            rx_valid_reg <= 1'b0;
            miso_reg     <= 1'b0;
        end else begin
            // 同步
            sclk_sync1 <= sclk;
            sclk_sync2 <= sclk_sync1;
            cs_n_sync1 <= cs_n;
            cs_n_sync2 <= cs_n_sync1;
            mosi_sync1 <= mosi;
            mosi_sync2 <= mosi_sync1;

            // 边沿检测
            sclk_sync2_d <= sclk_sync2;
            cs_n_sync2_d <= cs_n_sync2;

            // 默认
            rx_valid_reg <= 1'b0;

            if (cs_n_sync2) begin
                // 片选无效
                miso_reg <= 1'b0;
                bit_cnt  <= 4'b0;
            end else begin
                // 片选有效
                if (cs_n_neg) begin
                    tx_shift     <= tx_data;
                    bit_cnt      <= 4'b0;
                    miso_reg     <= tx_data[7];
                end else if (sclk_pos) begin
                    rx_shift <= {rx_shift[6:0], mosi_sync2};
                    if (bit_cnt == 4'd7) begin
                        rx_data_reg  <= {rx_shift[6:0], mosi_sync2};
                        rx_valid_reg <= 1'b1;
                        bit_cnt      <= 4'b0;
                        miso_reg     <= 1'b0;
                    end else begin
                        bit_cnt <= bit_cnt + 4'd1;
                    end
                end else if (sclk_neg) begin
                    if (bit_cnt < 4'd7) begin
                        miso_reg <= tx_shift[6 - bit_cnt[2:0]];
                    end else begin
                        miso_reg <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
