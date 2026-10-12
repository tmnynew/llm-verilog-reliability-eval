module spi_master #(parameter CLK_DIV = 4) (
    input clk,
    input rst_n,
    input start,
    input [7:0] tx_data,
    output reg [7:0] rx_data,
    output reg busy,
    output reg done,
    output reg sclk,
    output reg mosi,
    input miso,
    output reg cs_n
);

    // 状态定义
    localparam IDLE     = 2'd0;
    localparam TRANSFER = 2'd1;
    localparam DONE     = 2'd2;

    reg [1:0] state;
    reg [1:0] next_state;

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [2:0] bit_cnt;
    reg [15:0] clk_cnt;
    reg sclk_int;
    reg sclk_prev;
    reg sclk_rising;
    reg sclk_falling;

    // 状态机时序逻辑
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 状态机组合逻辑
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start && !busy)
                    next_state = TRANSFER;
            end
            TRANSFER: begin
                if (bit_cnt == 3'd7 && sclk_falling)
                    next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // 计数器与传输控制
    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            sclk <= 1'b0;
            cs_n <= 1'b1;
            mosi <= 1'b0;
            tx_shift <= 8'b0;
            rx_shift <= 8'b0;
            bit_cnt <= 3'd0;
            clk_cnt <= 16'd0;
            sclk_int <= 1'b0;
            sclk_prev <= 1'b0;
            sclk_rising <= 1'b0;
            sclk_falling <= 1'b0;
            rx_data <= 8'b0;
        end else begin
            sclk_prev <= sclk_int;
            sclk_rising <= (sclk_int && !sclk_prev);
            sclk_falling <= (!sclk_int && sclk_prev);

            case (state)
                IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    cs_n <= 1'b1;
                    sclk_int <= 1'b0;
                    sclk <= 1'b0;
                    clk_cnt <= 16'd0;
                    bit_cnt <= 3'd0;
                    if (start && !busy) begin
                        busy <= 1'b1;
                        cs_n <= 1'b0;
                        tx_shift <= tx_data;
                        rx_shift <= 8'b0;
                        mosi <= tx_data[7];
                        clk_cnt <= 16'd0;
                        sclk_int <= 1'b0;
                        sclk <= 1'b0;
                        bit_cnt <= 3'd0;
                    end
                end

                TRANSFER: begin
                    done <= 1'b0;
                    busy <= 1'b1;
                    cs_n <= 1'b0;

                    // 时钟计数器
                    if (clk_cnt == (CLK_DIV - 1)) begin
                        clk_cnt <= 16'd0;
                        sclk_int <= ~sclk_int;
                        sclk <= ~sclk_int;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end

                    // 在 sclk 上升沿采样 miso
                    if (sclk_rising) begin
                        rx_shift <= {rx_shift[6:0], miso};
                    end

                    // 在 sclk 下降沿切换 mosi
                    if (sclk_falling) begin
                        if (bit_cnt == 3'd7) begin
                            // 第8个下降沿，传输结束
                            mosi <= 1'b0;
                        end else begin
                            mosi <= tx_shift[6];
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end
                end

                DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    cs_n <= 1'b1;
                    sclk_int <= 1'b0;
                    sclk <= 1'b0;
                    rx_data <= rx_shift;
                    clk_cnt <= 16'd0;
                    bit_cnt <= 3'd0;
                end

                default: begin
                    busy <= 1'b0;
                    done <= 1'b0;
                    sclk <= 1'b0;
                    cs_n <= 1'b1;
                end
            endcase
        end
    end

endmodule
