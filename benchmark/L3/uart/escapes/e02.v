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

    // ---------------- TX ----------------
    localparam TX_IDLE = 3'd0;
    localparam TX_START = 3'd1;
    localparam TX_DATA = 3'd2;
    localparam TX_STOP = 3'd3;

    reg [2:0] tx_state;
    reg [15:0] tx_clk_cnt;
    reg [3:0] tx_bit_idx;
    reg [7:0] tx_shift;
    reg tx_busy_r;
    reg tx_r;

    assign tx_busy = tx_busy_r;
    assign tx = tx_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_state    <= TX_IDLE;
            tx_clk_cnt  <= 16'd0;
            tx_bit_idx  <= 4'd0;
            tx_shift    <= 8'd0;
            tx_busy_r   <= 1'b0;
            tx_r        <= 1'b1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_r       <= 1'b1;
                    tx_clk_cnt <= 16'd0;
                    tx_bit_idx <= 4'd0;
                    if (tx_start && !tx_busy_r) begin
                        tx_shift  <= tx_data;
                        tx_busy_r <= 1'b1;
                        tx_state  <= TX_START;
                    end
                end
                TX_START: begin
                    tx_r <= 1'b0;
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 16'd0;
                        tx_state   <= TX_DATA;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 16'd1;
                    end
                end
                TX_DATA: begin
                    tx_r <= tx_shift[0];
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 16'd0;
                        if (tx_bit_idx == 4'd7) begin
                            tx_state <= TX_STOP;
                        end else begin
                            tx_bit_idx <= tx_bit_idx + 4'd1;
                            tx_shift   <= {1'b0, tx_shift[7:1]};
                        end
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 16'd1;
                    end
                end
                TX_STOP: begin
                    tx_r <= 1'b1;
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 16'd0;
                        tx_busy_r  <= 1'b0;
                        tx_state   <= TX_IDLE;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 16'd1;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // ---------------- RX ----------------
    localparam RX_IDLE  = 3'd0;
    localparam RX_START = 3'd1;
    localparam RX_DATA  = 3'd2;
    localparam RX_STOP  = 3'd3;

    reg [2:0] rx_state;
    reg [15:0] rx_clk_cnt;
    reg [3:0] rx_bit_idx;
    reg [7:0] rx_shift;
    reg rx_valid_r;
    reg rx_err_r;
    reg [7:0] rx_data_r;

    assign rx_valid = rx_valid_r;
    assign rx_err   = rx_err_r;
    assign rx_data  = rx_data_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_state   <= RX_IDLE;
            rx_clk_cnt <= 16'd0;
            rx_bit_idx <= 4'd0;
            rx_shift   <= 8'd0;
            rx_valid_r <= 1'b0;
            rx_err_r   <= 1'b0;
            rx_data_r  <= 8'd0;
        end else begin
            rx_valid_r <= 1'b0;
            rx_err_r   <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    rx_clk_cnt <= 16'd0;
                    rx_bit_idx <= 4'd0;
                    if (rx == 1'b0) begin
                        rx_state <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_clk_cnt == (CLKS_PER_BIT >> 1) - 1) begin
                        rx_clk_cnt <= 16'd0;
                        if (rx == 1'b0) begin
                            rx_state <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 16'd1;
                    end
                end
                RX_DATA: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 16'd0;
                        rx_shift   <= {rx, rx_shift[7:1]};
                        if (rx_bit_idx == 4'd7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_idx <= rx_bit_idx + 4'd1;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 16'd1;
                    end
                end
                RX_STOP: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 16'd0;
                        if (rx == 1'b1) begin
                            rx_data_r  <= rx_shift;
                            rx_valid_r <= 1'b1;
                        end else begin
                            rx_err_r <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 16'd1;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule
