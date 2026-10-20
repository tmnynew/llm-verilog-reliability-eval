module spi_slave (
    input clk,
    input rst_n,
    input sclk,
    input cs_n,
    input mosi,
    output miso,
    input [7:0] tx_data,
    output [7:0] rx_data,
    output rx_valid
);

    reg sclk_sync1, sclk_sync2, sclk_sync3;
    reg cs_n_sync1, cs_n_sync2, cs_n_sync3;
    reg mosi_sync1, mosi_sync2;

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [3:0] bit_cnt;
    reg miso_reg;
    reg rx_valid_reg;

    wire sclk_pos = sclk_sync2 & ~sclk_sync3;
    wire sclk_neg = ~sclk_sync2 & sclk_sync3;
    wire cs_n_neg = cs_n_sync2 & ~cs_n_sync3;

    always @(posedge clk) begin
        if (!rst_n) begin
            sclk_sync1 <= 1'b0;
            sclk_sync2 <= 1'b0;
            sclk_sync3 <= 1'b0;
            cs_n_sync1 <= 1'b1;
            cs_n_sync2 <= 1'b1;
            cs_n_sync3 <= 1'b1;
            mosi_sync1 <= 1'b0;
            mosi_sync2 <= 1'b0;
        end else begin
            sclk_sync1 <= sclk;
            sclk_sync2 <= sclk_sync1;
            sclk_sync3 <= sclk_sync2;
            cs_n_sync1 <= cs_n;
            cs_n_sync2 <= cs_n_sync1;
            cs_n_sync3 <= cs_n_sync2;
            mosi_sync1 <= mosi;
            mosi_sync2 <= mosi_sync1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_shift <= 8'h00;
            bit_cnt  <= 4'd0;
            miso_reg <= 1'b0;
        end else begin
            if (cs_n_sync2) begin
                bit_cnt  <= 4'd0;
                miso_reg <= 1'b0;
            end else if (cs_n_neg) begin
                tx_shift <= tx_data;
                bit_cnt  <= 4'd0;
                miso_reg <= tx_data[7];
            end else if (sclk_pos) begin
                if (bit_cnt == 4'd7) begin
                    bit_cnt  <= 4'd0;
                    miso_reg <= 1'b0;
                end else begin
                    bit_cnt  <= bit_cnt + 4'd1;
                end
            end else if (sclk_neg) begin
                if (bit_cnt != 4'd0) begin
                    miso_reg <= tx_shift[7 - bit_cnt];
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_shift      <= 8'h00;
            rx_valid_reg  <= 1'b0;
        end else begin
            if (cs_n_sync2) begin
                rx_valid_reg <= 1'b0;
            end else if (sclk_pos) begin
                if (bit_cnt == 4'd7) begin
                    rx_shift     <= {rx_shift[6:0], mosi_sync2};
                    rx_valid_reg <= 1'b1;
                end else begin
                    rx_shift     <= {rx_shift[6:0], mosi_sync2};
                    rx_valid_reg <= 1'b0;
                end
            end else begin
                rx_valid_reg <= 1'b0;
            end
        end
    end

    assign miso      = miso_reg;
    assign rx_data   = rx_shift;
    assign rx_valid   = rx_valid_reg;

endmodule
