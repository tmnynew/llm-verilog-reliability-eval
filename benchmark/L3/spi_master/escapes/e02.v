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

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [7:0] rx_data_r;
    reg busy_r;
    reg done_r;
    reg sclk_r;
    reg cs_n_r;
    reg [3:0] bit_cnt;
    reg [31:0] clk_cnt;

    assign rx_data = rx_data_r;
    assign busy = busy_r;
    assign done = done_r;
    assign sclk = sclk_r;
    assign mosi = tx_shift[7];
    assign cs_n = cs_n_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_shift <= 8'h00;
            rx_shift <= 8'h00;
            rx_data_r <= 8'h00;
            busy_r <= 1'b0;
            done_r <= 1'b0;
            sclk_r <= 1'b0;
            cs_n_r <= 1'b1;
            bit_cnt <= 4'd0;
            clk_cnt <= 32'd0;
        end else begin
            done_r <= 1'b0;
            if (!busy_r) begin
                if (start) begin
                    tx_shift <= tx_data;
                    rx_shift <= 8'h00;
                    busy_r <= 1'b1;
                    cs_n_r <= 1'b0;
                    sclk_r <= 1'b0;
                    bit_cnt <= 4'd0;
                    clk_cnt <= 32'd0;
                end
            end else begin
                if (clk_cnt == CLK_DIV - 1) begin
                    clk_cnt <= 32'd0;
                    if (sclk_r) begin
                        rx_shift <= {rx_shift[6:0], miso};
                        if (bit_cnt == 4'd7) begin
                            busy_r <= 1'b0;
                            cs_n_r <= 1'b1;
                            sclk_r <= 1'b0;
                            rx_data_r <= {rx_shift[6:0], miso};
                            done_r <= 1'b1;
                            bit_cnt <= 4'd0;
                        end else begin
                            sclk_r <= 1'b0;
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end else begin
                        sclk_r <= 1'b1;
                        tx_shift <= {tx_shift[6:0], 1'b0};
                    end
                end else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end
        end
    end

endmodule
