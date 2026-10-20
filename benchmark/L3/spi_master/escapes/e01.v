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
    localparam IDLE = 2'd0;
    localparam TRANS = 2'd1;
    localparam DONE_ST = 2'd2;

    reg [1:0] state;
    reg [3:0] bit_cnt;          // 0~7 表示当前正在传输的位
    reg [15:0] clk_cnt;         // 用于产生 sclk 的计数器
    reg [7:0] tx_shift;         // 发送移位寄存器
    reg [7:0] rx_shift;         // 接收移位寄存器
    reg sclk_int;               // 内部 sclk 信号
    reg sclk_prev;              // 用于检测 sclk 边沿

    // 主状态机
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            cs_n <= 1'b1;
            sclk <= 1'b0;
            sclk_int <= 1'b0;
            sclk_prev <= 1'b0;
            mosi <= 1'b0;
            bit_cnt <= 4'd0;
            clk_cnt <= 16'd0;
            tx_shift <= 8'd0;
            rx_shift <= 8'd0;
            rx_data <= 8'd0;
        end else begin
            done <= 1'b0; // 默认 done 为 0

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    cs_n <= 1'b1;
                    sclk <= 1'b0;
                    sclk_int <= 1'b0;
                    sclk_prev <= 1'b0;
                    mosi <= 1'b0;
                    bit_cnt <= 4'd0;
                    clk_cnt <= 16'd0;
                    if (start) begin
                        // 接受传输
                        tx_shift <= tx_data;
                        rx_shift <= 8'd0;
                        busy <= 1'b1;
                        cs_n <= 1'b0;
                        mosi <= tx_data[7];
                        state <= TRANS;
                        clk_cnt <= 16'd0;
                        bit_cnt <= 4'd0;
                        sclk_int <= 1'b0;
                        sclk_prev <= 1'b0;
                    end
                end

                TRANS: begin
                    busy <= 1'b1;
                    cs_n <= 1'b0;
                    sclk_prev <= sclk_int;

                    // 计数器控制 sclk
                    if (clk_cnt == CLK_DIV - 1) begin
                        clk_cnt <= 16'd0;
                        sclk_int <= ~sclk_int;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end

                    // 检测 sclk 上升沿：采样 miso
                    if (sclk_prev == 1'b0 && sclk_int == 1'b1) begin
                        rx_shift <= {rx_shift[6:0], miso};
                    end

                    // 检测 sclk 下降沿：切换 mosi，并计数
                    if (sclk_prev == 1'b1 && sclk_int == 1'b0) begin
                        if (bit_cnt == 4'd7) begin
                            // 第 8 个下降沿，传输结束
                            state <= DONE_ST;
                            done <= 1'b1;
                            rx_data <= {rx_shift[6:0], miso}; // 注意：最后一个上升沿已经采样了最后一位
                            // 修正：最后一个上升沿采样的是第 8 位，此时 rx_shift 已经包含了前 7 位
                            // 但我们需要在下降沿时完成，所以需要重新计算
                            // 实际上，在第 8 个上升沿时，rx_shift 已经更新为完整的 8 位
                            // 这里直接使用 rx_shift 即可
                            rx_data <= rx_shift;
                            sclk <= 1'b0;
                            sclk_int <= 1'b0;
                            cs_n <= 1'b1;
                            busy <= 1'b0;
                            mosi <= 1'b0;
                        end else begin
                            bit_cnt <= bit_cnt + 4'd1;
                            mosi <= tx_shift[6 - bit_cnt];
                        end
                    end

                    // 更新 sclk 输出
                    sclk <= sclk_int;
                end

                DONE_ST: begin
                    // done 已经在上一个周期输出，这里回到 IDLE
                    done <= 1'b0;
                    busy <= 1'b0;
                    cs_n <= 1'b1;
                    sclk <= 1'b0;
                    sclk_int <= 1'b0;
                    sclk_prev <= 1'b0;
                    mosi <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
