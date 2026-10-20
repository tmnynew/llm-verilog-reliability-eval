module uart #(parameter CLKS_PER_BIT = 16) (
    input clk,
    input rst_n,
    input tx_start,
    input [7:0] tx_data,
    output reg tx_busy,
    output reg tx,
    input rx,
    output reg [7:0] rx_data,
    output reg rx_valid,
    output reg rx_err
);
    // 发送状态机
    localparam TX_IDLE = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA = 2'd2;
    localparam TX_STOP = 2'd3;

    reg [1:0] tx_state;
    reg [3:0] tx_bit_cnt;
    reg [15:0] tx_clk_cnt;
    reg [7:0] tx_shift_reg;

    // 接收状态机
    localparam RX_IDLE = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA = 2'd2;
    localparam RX_STOP = 2'd3;

    reg [1:0] rx_state;
    reg [3:0] rx_bit_cnt;
    reg [15:0] rx_clk_cnt;
    reg [7:0] rx_shift_reg;
    reg rx_start_detected;

    // 发送逻辑
    always @(posedge clk) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_busy <= 1'b0;
            tx <= 1'b1;
            tx_clk_cnt <= 16'd0;
            tx_bit_cnt <= 4'd0;
            tx_shift_reg <= 8'd0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        tx_busy <= 1'b1;
                        tx_state <= TX_START;
                        tx_clk_cnt <= 16'd0;
                        tx_bit_cnt <= 4'd0;
                    end
                end

                TX_START: begin
                    tx <= 1'b0;
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 16'd0;
                        tx_state <= TX_DATA;
                        tx_bit_cnt <= 4'd0;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end
                end

                TX_DATA: begin
                    tx <= tx_shift_reg[0];
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 16'd0;
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        if (tx_bit_cnt == 4'd7) begin
                            tx_state <= TX_STOP;
                            tx_bit_cnt <= 4'd0;
                        end else begin
                            tx_bit_cnt <= tx_bit_cnt + 1'b1;
                        end
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end
                end

                TX_STOP: begin
                    tx <= 1'b1;
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 16'd0;
                        tx_busy <= 1'b0;
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end
                end

                default: begin
                    tx_state <= TX_IDLE;
                    tx_busy <= 1'b0;
                    tx <= 1'b1;
                end
            endcase
        end
    end

    // 接收逻辑
    always @(posedge clk) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_clk_cnt <= 16'd0;
            rx_bit_cnt <= 4'd0;
            rx_shift_reg <= 8'd0;
            rx_valid <= 1'b0;
            rx_err <= 1'b0;
            rx_data <= 8'd0;
            rx_start_detected <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            rx_err <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    rx_clk_cnt <= 16'd0;
                    rx_bit_cnt <= 4'd0;
                    if (rx == 1'b0) begin
                        rx_state <= RX_START;
                        rx_clk_cnt <= 16'd0;
                    end
                end

                RX_START: begin
                    if (rx_clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        if (rx == 1'b0) begin
                            rx_clk_cnt <= 16'd0;
                            rx_bit_cnt <= 4'd0;
                            rx_state <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end

                RX_DATA: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 16'd0;
                        rx_shift_reg <= {rx, rx_shift_reg[7:1]};
                        if (rx_bit_cnt == 4'd7) begin
                            rx_state <= RX_STOP;
                            rx_bit_cnt <= 4'd0;
                        end else begin
                            rx_bit_cnt <= rx_bit_cnt + 1'b1;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end

                RX_STOP: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 16'd0;
                        if (rx == 1'b1) begin
                            rx_data <= rx_shift_reg;
                            rx_valid <= 1'b1;
                        end else begin
                            rx_err <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end

                default: begin
                    rx_state <= RX_IDLE;
                end
            endcase
        end
    end

endmodule
