module uart #(parameter CLKS_PER_BIT = 16) (
    input clk,
    input rst_n,
    input tx_start,
    input [7:0] tx_data,
    output tx_busy,
    output tx,
    input rx,
    output [7:0] rx_data,
    output rx_valid,
    output rx_err
);

    // 发送相关信号
    reg [2:0] tx_state;
    reg [3:0] tx_bit_cnt;
    reg [3:0] tx_clk_cnt;
    reg [7:0] tx_shift_reg;
    reg tx_busy_r;
    reg tx_out;
    
    // 接收相关信号
    reg [2:0] rx_state;
    reg [3:0] rx_bit_cnt;
    reg [3:0] rx_clk_cnt;
    reg [7:0] rx_shift_reg;
    reg rx_sample_d1, rx_sample_d2;
    reg rx_data_valid;
    reg rx_err_r;
    reg [7:0] rx_data_r;
    
    parameter TX_IDLE = 3'b000,
              TX_START = 3'b001,
              TX_DATA = 3'b010,
              TX_STOP = 3'b011;
              
    parameter RX_IDLE = 3'b000,
              RX_START = 3'b001,
              RX_DATA = 3'b010,
              RX_STOP = 3'b011;

    // 同步rx输入
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sample_d1 <= 1'b1;
            rx_sample_d2 <= 1'b1;
        end else begin
            rx_sample_d1 <= rx;
            rx_sample_d2 <= rx_sample_d1;
        end
    end

    // 发送状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_bit_cnt <= 0;
            tx_clk_cnt <= 0;
            tx_shift_reg <= 0;
            tx_busy_r <= 1'b0;
            tx_out <= 1'b1; // idle state is high
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_out <= 1'b1;
                    tx_busy_r <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        tx_bit_cnt <= 0;
                        tx_clk_cnt <= 0;
                        tx_busy_r <= 1'b1;
                        tx_out <= 1'b0; // start bit
                        tx_state <= TX_START;
                    end
                end
                TX_START: begin
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        tx_out <= tx_shift_reg[0];
                        tx_state <= TX_DATA;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end
                end
                TX_DATA: begin
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        if (tx_bit_cnt == 7) begin
                            tx_out <= 1'b1; // stop bit
                            tx_state <= TX_STOP;
                        end else begin
                            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            tx_out <= tx_shift_reg[0];
                            tx_bit_cnt <= tx_bit_cnt + 1;
                        end
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end
                end
                TX_STOP: begin
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // 接收状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_bit_cnt <= 0;
            rx_clk_cnt <= 0;
            rx_shift_reg <= 0;
            rx_data_valid <= 1'b0;
            rx_err_r <= 1'b0;
            rx_data_r <= 8'b0;
        end else begin
            rx_data_valid <= 1'b0; // default to 0
            case (rx_state)
                RX_IDLE: begin
                    if (rx_sample_d2 == 1'b0) begin // detect start bit
                        rx_clk_cnt <= 0;
                        rx_bit_cnt <= 0;
                        rx_shift_reg <= 0;
                        rx_state <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_clk_cnt == (CLKS_PER_BIT >> 1)) begin // sample at middle of start bit
                        if (rx_sample_d2 == 1'b0) begin // confirm start bit
                            rx_clk_cnt <= 0;
                            rx_state <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE; // not a valid start bit
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end
                end
                RX_DATA: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 0;
                        rx_shift_reg <= {rx_sample_d2, rx_shift_reg[7:1]};
                        if (rx_bit_cnt == 7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_cnt <= rx_bit_cnt + 1;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end
                end
                RX_STOP: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        if (rx_sample_d2 == 1'b1) begin // check stop bit
                            rx_data_r <= rx_shift_reg;
                            rx_data_valid <= 1'b1;
                            rx_err_r <= 1'b0;
                        end else begin
                            rx_err_r <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    assign tx_busy = tx_busy_r;
    assign tx = tx_out;
    assign rx_data = rx_data_r;
    assign rx_valid = rx_data_valid;
    assign rx_err = rx_err_r;

endmodule
