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

    reg cs_n_d;
    reg sclk_d;

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [3:0] bit_cnt;

    reg cs_n_active;

    reg miso_reg;
    reg [7:0] rx_data_reg;
    reg rx_valid_reg;

    assign miso = miso_reg;
    assign rx_data = rx_data_reg;
    assign rx_valid = rx_valid_reg;

    wire cs_n_fall = (~cs_n_sync2 & cs_n_sync3);
    wire sclk_rise = ( sclk_sync2 & ~sclk_sync3);
    wire sclk_fall = (~sclk_sync2 & sclk_sync3);

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
            cs_n_d      <= 1'b1;
            sclk_d      <= 1'b0;
            tx_shift    <= 8'b0;
            rx_shift    <= 8'b0;
            bit_cnt     <= 4'b0;
            cs_n_active <= 1'b0;
            miso_reg    <= 1'b0;
            rx_data_reg <= 8'b0;
            rx_valid_reg<= 1'b0;
        end else begin
            cs_n_d <= cs_n_sync2;
            sclk_d <= sclk_sync2;

            rx_valid_reg <= 1'b0;

            if (cs_n_fall) begin
                tx_shift    <= tx_data;
                bit_cnt     <= 4'b0;
                cs_n_active <= 1'b1;
                miso_reg    <= tx_data[7];
            end else if (cs_n_sync2 == 1'b1) begin
                cs_n_active <= 1'b0;
                miso_reg   <= 1'b0;
                bit_cnt     <= 4'b0;
            end else if (cs_n_active) begin
                if (sclk_rise) begin
                    rx_shift <= {rx_shift[6:0], mosi_sync2};
                    if (bit_cnt == 4'd7) begin
                        rx_data_reg  <= {rx_shift[6:0], mosi_sync2};
                        rx_valid_reg <= 1'b1;
                        bit_cnt       <= 4'b0;
                    end else begin
                        bit_cnt <= bit_cnt + 4'd1;
                    end
                end else if (sclk_fall) begin
                    if (bit_cnt == 4'd7) begin
                        miso_reg <= 1'b0;
                    end else begin
                        miso_reg <= tx_shift[6];
                    end
                    tx_shift <= {tx_shift[6:0], 1'b0};
                end
            end
        end
    end

endmodule
