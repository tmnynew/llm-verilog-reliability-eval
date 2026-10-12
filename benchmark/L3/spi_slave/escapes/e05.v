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

    reg [1:0] sclk_sync, cs_n_sync;
    reg mosi_sync;
    reg [2:0] bit_cnt;
    reg [7:0] rx_shift_reg;
    reg [7:0] tx_shift_reg;
    reg miso_reg;
    reg [7:0] rx_data_reg;
    reg rx_valid_reg;
    
    // 同步异步信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= 2'b00;
            cs_n_sync <= 2'b11;
            mosi_sync <= 1'b0;
        end else begin
            sclk_sync <= {sclk_sync[0], sclk};
            cs_n_sync <= {cs_n_sync[0], cs_n};
            mosi_sync <= mosi;
        end
    end
    
    // 检测sclk上升沿和cs_n下降沿
    wire sclk_pos_edge = (sclk_sync[1] == 1'b0 && sclk_sync[0] == 1'b1);
    wire cs_n_fall_edge = (cs_n_sync[1] == 1'b1 && cs_n_sync[0] == 1'b0);
    
    // 状态机
    parameter IDLE = 2'b00, TRANSMIT = 2'b01, RECEIVE = 2'b10;
    reg [1:0] state;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 3'd0;
            rx_shift_reg <= 8'h00;
            tx_shift_reg <= 8'h00;
            miso_reg <= 1'b0;
            rx_data_reg <= 8'h00;
            rx_valid_reg <= 1'b0;
        end else begin
            rx_valid_reg <= 1'b0; // 默认清零
            
            case (state)
                IDLE: begin
                    if (!cs_n_sync[0]) begin // cs_n拉低
                        state <= TRANSMIT;
                        bit_cnt <= 3'd0;
                        tx_shift_reg <= tx_data;
                        rx_shift_reg <= 8'h00;
                        miso_reg <= tx_shift_reg[7];
                    end
                end
                
                TRANSMIT: begin
                    if (sclk_pos_edge) begin
                        // 移位输出
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                        miso_reg <= tx_shift_reg[6]; // 下一位
                        
                        // 移位输入
                        rx_shift_reg <= {rx_shift_reg[6:0], mosi_sync};
                        
                        bit_cnt <= bit_cnt + 1'b1;
                        
                        if (bit_cnt == 3'd6) begin // 已经传输了7位，下一次就是第8位
                            state <= RECEIVE;
                        end
                    end
                end
                
                RECEIVE: begin
                    if (sclk_pos_edge) begin
                        // 最后一位处理
                        rx_shift_reg <= {rx_shift_reg[6:0], mosi_sync};
                        bit_cnt <= bit_cnt + 1'b1;
                        
                        if (bit_cnt == 3'd7) begin // 8位已收完
                            rx_data_reg <= {rx_shift_reg[6:0], mosi_sync};
                            rx_valid_reg <= 1'b1;
                            
                            if (cs_n_sync[0]) begin // 如果cs_n已经释放则回到空闲
                                state <= IDLE;
                                miso_reg <= 1'b0;
                            end else begin // 否则继续等待
                                state <= IDLE;
                                miso_reg <= 1'b0;
                            end
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
            
            // 如果cs_n在传输过程中被拉高，则立即回到空闲状态
            if (cs_n_sync[0] && !cs_n_sync[1]) begin // cs_n上升沿
                state <= IDLE;
                miso_reg <= 1'b0;
            end
        end
    end

    assign miso = miso_reg;
    assign rx_data = rx_data_reg;
    assign rx_valid = rx_valid_reg;

endmodule
