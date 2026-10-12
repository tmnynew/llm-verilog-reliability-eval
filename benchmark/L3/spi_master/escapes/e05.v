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
    reg [7:0] rx_data_r;
    reg busy_r;
    reg done_r;
    reg sclk_r;
    reg [2:0] bit_cnt;
    reg [7:0] tx_shift;
    reg mosi_r;
    reg cs_n_r;
    reg [31:0] sclk_cnt; // 使用足够大的位宽支持大CLK_DIV
    
    parameter IDLE = 3'b000;
    parameter START = 3'b001;
    parameter TRANSMIT = 3'b010;
    parameter DONE = 3'b011;

    assign rx_data = rx_data_r;
    assign busy = busy_r;
    assign done = done_r;
    assign sclk = sclk_r;
    assign mosi = mosi_r;
    assign cs_n = cs_n_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            rx_data_r <= 8'b0;
            busy_r <= 1'b0;
            done_r <= 1'b0;
            sclk_r <= 1'b0;
            bit_cnt <= 3'b0;
            tx_shift <= 8'b0;
            mosi_r <= 1'b0;
            cs_n_r <= 1'b1;
            sclk_cnt <= 32'b0;
        end else begin
            case (state)
                IDLE: begin
                    done_r <= 1'b0;
                    if (start && !busy_r) begin
                        busy_r <= 1'b1;
                        cs_n_r <= 1'b0;
                        tx_shift <= tx_data;
                        rx_data_r <= 8'b0;
                        bit_cnt <= 3'b0;
                        mosi_r <= tx_data[7];
                        sclk_cnt <= 32'b0;
                        sclk_r <= 1'b0;
                        state <= START;
                    end
                end
                
                START: begin
                    if (sclk_cnt == CLK_DIV - 1) begin
                        sclk_r <= 1'b1;
                        sclk_cnt <= 32'b0;
                        state <= TRANSMIT;
                    end else begin
                        sclk_cnt <= sclk_cnt + 1;
                    end
                end
                
                TRANSMIT: begin
                    if (sclk_r == 1'b1) begin // SCLK上升沿 - 采样MISO
                        rx_data_r[7-bit_cnt] <= miso;
                        if (bit_cnt == 3'b111) begin // 最后一位
                            sclk_r <= 1'b0;
                            cs_n_r <= 1'b1;
                            state <= DONE;
                        end else begin
                            sclk_r <= 1'b0;
                        end
                    end else if (sclk_r == 1'b0) begin // SCLK下降沿 - 更新MOSI
                        if (sclk_cnt == CLK_DIV - 1) begin
                            bit_cnt <= bit_cnt + 1;
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            mosi_r <= tx_shift[6]; // 下一位
                            sclk_r <= 1'b1;
                            sclk_cnt <= 32'b0;
                        end else begin
                            sclk_cnt <= sclk_cnt + 1;
                        end
                    end
                end
                
                DONE: begin
                    done_r <= 1'b1;
                    state <= IDLE;
                    busy_r <= 1'b0;
                    cs_n_r <= 1'b1;
                    sclk_r <= 1'b0;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
            
            if (!rst_n) begin
                state <= IDLE;
                busy_r <= 1'b0;
                cs_n_r <= 1'b1;
                sclk_r <= 1'b0;
            end
        end
    end

endmodule
