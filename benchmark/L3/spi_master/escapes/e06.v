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

    reg [2:0] state;
    reg [2:0] bit_cnt;
    reg [4:0] clk_div_cnt;
    reg [7:0] rx_data_r;
    reg busy_r;
    reg done_r;
    reg sclk_r;
    reg mosi_r;
    reg cs_n_r;

    parameter IDLE = 3'b000;
    parameter START = 3'b001;
    parameter TRANSMIT = 3'b010;
    parameter STOP = 3'b011;

    assign rx_data = rx_data_r;
    assign busy = busy_r;
    assign done = done_r;
    assign sclk = sclk_r;
    assign mosi = mosi_r;
    assign cs_n = cs_n_r;

    wire clk_div_end = (clk_div_cnt == (CLK_DIV * 2 - 1));
    wire bit_done = (bit_cnt == 3'd7) && clk_div_end && (state == TRANSMIT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 3'd0;
            clk_div_cnt <= 5'd0;
            rx_data_r <= 8'd0;
            busy_r <= 1'b0;
            done_r <= 1'b0;
            sclk_r <= 1'b0;
            mosi_r <= 1'b0;
            cs_n_r <= 1'b1;
        end else begin
            done_r <= 1'b0; // default to clear done pulse
            
            case (state)
                IDLE: begin
                    busy_r <= 1'b0;
                    cs_n_r <= 1'b1;
                    sclk_r <= 1'b0;
                    if (start) begin
                        state <= START;
                        busy_r <= 1'b1;
                        clk_div_cnt <= 5'd0;
                    end
                end
                
                START: begin
                    cs_n_r <= 1'b0;
                    mosi_r <= tx_data[7];
                    rx_data_r <= {rx_data_r[6:0], miso};
                    sclk_r <= 1'b0;
                    bit_cnt <= 3'd0;
                    clk_div_cnt <= clk_div_cnt + 1'b1;
                    if (clk_div_end) begin
                        state <= TRANSMIT;
                        clk_div_cnt <= 5'd0;
                    end
                end
                
                TRANSMIT: begin
                    if (clk_div_end) begin
                        if (bit_cnt < 3'd7) begin
                            bit_cnt <= bit_cnt + 1'b1;
                            clk_div_cnt <= 5'd0;
                            rx_data_r <= {rx_data_r[6:0], miso};
                            mosi_r <= tx_data[7-bit_cnt-1];
                        end else begin
                            clk_div_cnt <= 5'd0;
                            rx_data_r <= {rx_data_r[6:0], miso};
                            mosi_r <= tx_data[0]; // last bit
                            state <= STOP;
                        end
                    end else begin
                        clk_div_cnt <= clk_div_cnt + 1'b1;
                        if (clk_div_cnt >= CLK_DIV) begin
                            sclk_r <= 1'b1;
                        end else begin
                            sclk_r <= 1'b0;
                        end
                    end
                end
                
                STOP: begin
                    cs_n_r <= 1'b1;
                    sclk_r <= 1'b0;
                    busy_r <= 1'b0;
                    done_r <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
