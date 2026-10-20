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

    // TX signals
    reg [3:0] tx_state;
    reg [3:0] tx_bit_cnt;
    reg [3:0] tx_clk_cnt;
    reg [7:0] tx_shift_reg;
    reg tx_busy_r;
    reg tx_out;

    // RX signals
    reg [4:0] rx_state;
    reg [3:0] rx_bit_cnt;
    reg [3:0] rx_clk_cnt;
    reg [9:0] rx_shift_reg; // start bit + 8 data bits + stop bit
    reg rx_sample_point;
    reg [7:0] rx_data_r;
    reg rx_valid_r;
    reg rx_err_r;

    // TX FSM
    parameter TX_IDLE = 4'd0,
              TX_START = 4'd1,
              TX_DATA = 4'd2,
              TX_STOP = 4'd3;

    // RX FSM
    parameter RX_IDLE = 5'd0,
              RX_WAIT_START = 5'd1,
              RX_SAMPLE_START = 5'd2,
              RX_DATA = 5'd3,
              RX_SAMPLE_STOP = 5'd4;

    // TX logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_bit_cnt <= 4'd0;
            tx_clk_cnt <= 4'd0;
            tx_shift_reg <= 8'd0;
            tx_busy_r <= 1'b0;
            tx_out <= 1'b1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_busy_r <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        tx_bit_cnt <= 4'd0;
                        tx_clk_cnt <= 4'd0;
                        tx_out <= 1'b0; // Start bit
                        tx_busy_r <= 1'b1;
                        tx_state <= TX_START;
                    end
                end
                TX_START: begin
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 4'd0;
                        tx_out <= tx_shift_reg[0];
                        tx_state <= TX_DATA;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end
                end
                TX_DATA: begin
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 4'd0;
                        if (tx_bit_cnt < 7) begin
                            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            tx_out <= tx_shift_reg[0];
                            tx_bit_cnt <= tx_bit_cnt + 1'b1;
                        end else begin
                            tx_out <= 1'b1; // Stop bit
                            tx_state <= TX_STOP;
                        end
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end
                end
                TX_STOP: begin
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // RX logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_bit_cnt <= 4'd0;
            rx_clk_cnt <= 4'd0;
            rx_shift_reg <= 10'd0;
            rx_data_r <= 8'd0;
            rx_valid_r <= 1'b0;
            rx_err_r <= 1'b0;
            rx_sample_point <= 1'b0;
        end else begin
            rx_valid_r <= 1'b0;
            rx_sample_point <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (!rx) begin // Found start bit
                        rx_clk_cnt <= CLKS_PER_BIT / 2; // Wait half a bit period to center sample
                        rx_state <= RX_WAIT_START;
                    end
                end
                RX_WAIT_START: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 4'd0;
                        if (!rx) begin // Verify start bit still low
                            rx_shift_reg <= 10'd0;
                            rx_bit_cnt <= 4'd0;
                            rx_sample_point <= 1'b1;
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
                        rx_clk_cnt <= 4'd0;
                        rx_shift_reg <= {rx, rx_shift_reg[9:1]};
                        rx_sample_point <= 1'b1;
                        if (rx_bit_cnt < 8) begin
                            rx_bit_cnt <= rx_bit_cnt + 1'b1;
                        end else begin
                            rx_state <= RX_SAMPLE_STOP;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end
                RX_SAMPLE_STOP: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_data_r <= rx_shift_reg[8:1]; // Data bits
                        rx_valid_r <= 1'b1;
                        rx_err_r <= ~rx; // Error if stop bit is not high
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    assign tx_busy = tx_busy_r;
    assign tx = tx_out;
    assign rx_data = rx_data_r;
    assign rx_valid = rx_valid_r;
    assign rx_err = rx_err_r;

endmodule
