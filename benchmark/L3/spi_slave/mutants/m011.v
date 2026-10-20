// MUTANT m011 CRP line 38: "1'b0" -> "1'b1"
// Golden reference: oversampled SPI slave, mode 0, MSB first
module spi_slave (
    input            clk,
    input            rst_n,
    input            sclk,
    input            cs_n,
    input            mosi,
    output           miso,
    input      [7:0] tx_data,
    output reg [7:0] rx_data,
    output reg       rx_valid
);
    reg [2:0] sclk_s, cs_s;
    reg [1:0] mosi_s;
    reg [7:0] tx_sh, rx_sh;
    reg [2:0] bit_cnt;

    wire sclk_rise = sclk_s[1] & ~sclk_s[2];
    wire sclk_fall = ~sclk_s[1] & sclk_s[2];
    wire cs_fall   = ~cs_s[1] & cs_s[2];
    wire cs_act    = ~cs_s[1];
    wire mosi_sync = mosi_s[1];

    always @(posedge clk) begin
        if (!rst_n) begin
            sclk_s <= 3'b000;
            cs_s   <= 3'b111;
            mosi_s <= 2'b00;
        end else begin
            sclk_s <= {sclk_s[1:0], sclk};
            cs_s   <= {cs_s[1:0], cs_n};
            mosi_s <= {mosi_s[0], mosi};
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_valid <= 1'b1;
            rx_data  <= 8'd0;
            tx_sh    <= 8'd0;
            rx_sh    <= 8'd0;
            bit_cnt  <= 3'd0;
        end else begin
            rx_valid <= 1'b0;
            if (cs_fall) begin
                tx_sh   <= tx_data;
                bit_cnt <= 3'd0;
            end else if (cs_act) begin
                if (sclk_rise) begin
                    rx_sh   <= {rx_sh[6:0], mosi_sync};
                    bit_cnt <= bit_cnt + 3'd1;
                    if (bit_cnt == 3'd7) begin
                        rx_data  <= {rx_sh[6:0], mosi_sync};
                        rx_valid <= 1'b1;
                    end
                end
                if (sclk_fall)
                    tx_sh <= {tx_sh[6:0], 1'b0};
            end
        end
    end

    assign miso = cs_act ? tx_sh[7] : 1'b0;
endmodule
