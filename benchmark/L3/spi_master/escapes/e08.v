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
    reg [5:0] clk_cnt;
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 0;
            clk_cnt <= 0;
            rx_data_r <= 0;
            busy_r <= 0;
            done_r <= 0;
            sclk_r <= 0;
            mosi_r <= 0;
            cs_n_r <= 1;
        end else begin
            case (state)
                IDLE: begin
                    done_r <= 0;
                    if (start) begin
                        state <= START;
                        busy_r <= 1;
                        cs_n_r <= 0;
                        bit_cnt <= 0;
                        clk_cnt <= 0;
                        rx_data_r <= 0;
                        mosi_r <= tx_data[7];
                        sclk_r <= 0;
                    end
                end
                
                START: begin
                    state <= TRANSMIT;
                    clk_cnt <= 1; // Start counting from 1 to get proper timing
                    sclk_r <= 0;
                end
                
                TRANSMIT: begin
                    if (clk_cnt == CLK_DIV - 1) begin
                        sclk_r <= ~sclk_r; // Toggle sclk
                        clk_cnt <= 0;
                        
                        if (sclk_r == 0) begin // Rising edge of sclk - capture data
                            rx_data_r[7-bit_cnt] <= miso;
                        end else begin // Falling edge of sclk - change data
                            if (bit_cnt < 7) begin
                                bit_cnt <= bit_cnt + 1;
                                mosi_r <= tx_data[7-bit_cnt-1];
                            end else begin
                                state <= STOP;
                            end
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                
                STOP: begin
                    cs_n_r <= 1;
                    busy_r <= 0;
                    done_r <= 1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
