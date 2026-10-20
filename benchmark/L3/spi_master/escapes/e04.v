module spi_master #(parameter CLK_DIV = 4) (
    input clk,
    input rst_n,
    input start,
    input [7:0] tx_data,
    output [7:0] rx_data,
    output busy,
    output done,
    output sclk,
    output mosi,
    input miso,
    output cs_n
);

    reg [2:0] state;
    reg [2:0] next_state;
    
    // 状态定义
    parameter IDLE = 3'b000;
    parameter START = 3'b001;
    parameter TRANSMIT = 3'b010;
    parameter SAMPLE = 3'b011;
    parameter FINISH = 3'b100;
    
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg [7:0] rx_shift_reg;
    reg [CLK_DIV-1:0] clk_div_cnt;
    reg sclk_reg;
    reg mosi_reg;
    reg cs_n_reg;
    reg busy_reg;
    reg done_reg;
    
    assign rx_data = rx_shift_reg;
    assign busy = busy_reg;
    assign done = done_reg;
    assign sclk = sclk_reg;
    assign mosi = mosi_reg;
    assign cs_n = cs_n_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 0;
            shift_reg <= 0;
            rx_shift_reg <= 0;
            clk_div_cnt <= 0;
            sclk_reg <= 0;
            mosi_reg <= 0;
            cs_n_reg <= 1;
            busy_reg <= 0;
            done_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= START;
                        shift_reg <= tx_data;
                        rx_shift_reg <= 0;
                        bit_cnt <= 0;
                        clk_div_cnt <= 0;
                        sclk_reg <= 0;
                        mosi_reg <= shift_reg[7];
                        cs_n_reg <= 0;
                        busy_reg <= 1;
                        done_reg <= 0;
                    end else begin
                        done_reg <= 0;
                    end
                end
                
                START: begin
                    if (clk_div_cnt == (CLK_DIV - 1)/2) begin
                        sclk_reg <= 1;  // SCLK上升沿，采样数据
                        state <= SAMPLE;
                        clk_div_cnt <= 0;
                    end else begin
                        clk_div_cnt <= clk_div_cnt + 1;
                    end
                end
                
                SAMPLE: begin
                    if (clk_div_cnt == CLK_DIV - 1) begin
                        rx_shift_reg <= {rx_shift_reg[6:0], miso};
                        if (bit_cnt < 7) begin
                            bit_cnt <= bit_cnt + 1;
                            state <= TRANSMIT;
                            sclk_reg <= 0;
                            clk_div_cnt <= 0;
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            mosi_reg <= shift_reg[6];  // 下一位
                        end else begin
                            state <= FINISH;
                            sclk_reg <= 0;
                            clk_div_cnt <= 0;
                        end
                    end else begin
                        clk_div_cnt <= clk_div_cnt + 1;
                    end
                end
                
                TRANSMIT: begin
                    if (clk_div_cnt == (CLK_DIV - 1)/2) begin
                        sclk_reg <= 1;  // SCLK上升沿，准备下一次采样
                        state <= SAMPLE;
                        clk_div_cnt <= 0;
                    end else begin
                        clk_div_cnt <= clk_div_cnt + 1;
                    end
                end
                
                FINISH: begin
                    if (clk_div_cnt == CLK_DIV - 1) begin
                        cs_n_reg <= 1;
                        busy_reg <= 0;
                        done_reg <= 1;
                        state <= IDLE;
                    end else begin
                        clk_div_cnt <= clk_div_cnt + 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
            
            if (start && state == IDLE) begin
                // 在IDLE状态且start有效时设置初始值
                shift_reg <= tx_data;
                rx_shift_reg <= 0;
                bit_cnt <= 0;
                clk_div_cnt <= 0;
                sclk_reg <= 0;
                mosi_reg <= tx_data[7];
                cs_n_reg <= 0;
                busy_reg <= 1;
                done_reg <= 0;
            end
        end
    end

endmodule
