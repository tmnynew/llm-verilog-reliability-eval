// MUTANT m018 SDL line 61: "bit_cnt <= bit_cnt + 3'd1;" -> '/* statement removed */'
// Golden reference: SPI master, mode 0, MSB first, single chip select
module spi_master #(
    parameter CLK_DIV = 4
) (
    input            clk,
    input            rst_n,
    input            start,
    input      [7:0] tx_data,
    output reg [7:0] rx_data,
    output           busy,
    output reg       done,
    output reg       sclk,
    output           mosi,
    input            miso,
    output reg       cs_n
);
    reg        active;
    reg [7:0]  sh, rx_sh;
    reg [2:0]  bit_cnt;
    reg [15:0] div_cnt;

    assign busy = active;
    assign mosi = sh[7];

    always @(posedge clk) begin
        if (!rst_n) begin
            active  <= 1'b0;
            sclk    <= 1'b0;
            cs_n    <= 1'b1;
            done    <= 1'b0;
            div_cnt <= 16'd0;
            bit_cnt <= 3'd0;
            sh      <= 8'd0;
            rx_sh   <= 8'd0;
            rx_data <= 8'd0;
        end else begin
            done <= 1'b0;
            if (!active) begin
                sclk <= 1'b0;
                if (start) begin
                    active  <= 1'b1;
                    cs_n    <= 1'b0;
                    sh      <= tx_data;
                    bit_cnt <= 3'd0;
                    div_cnt <= 16'd0;
                end
            end else if (div_cnt == CLK_DIV - 1) begin
                div_cnt <= 16'd0;
                if (!sclk) begin
                    sclk  <= 1'b1;
                    rx_sh <= {rx_sh[6:0], miso};
                end else begin
                    sclk <= 1'b0;
                    if (bit_cnt == 3'd7) begin
                        active  <= 1'b0;
                        cs_n    <= 1'b1;
                        done    <= 1'b1;
                        rx_data <= rx_sh;
                    end else begin
                        sh      <= {sh[6:0], 1'b0};
                        /* statement removed */
                    end
                end
            end else begin
                div_cnt <= div_cnt + 16'd1;
            end
        end
    end
endmodule
