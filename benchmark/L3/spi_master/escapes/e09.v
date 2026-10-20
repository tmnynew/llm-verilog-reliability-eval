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
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg [3:0] clk_cnt;
    reg busy_r;
    reg done_r;
    reg sclk_r;
    reg mosi_r;
    reg cs_n_r;
    
    parameter IDLE = 3'd0,
              START = 3'd1,
              TX_RX = 3'd2,
              END = 3'd3;
    
    assign busy = busy_r;
    assign done = done_r;
    assign sclk = sclk_r;
    assign mosi = mosi_r;
    assign cs_n = cs_n_r;
    
    wire clk_en = (clk_cnt == (CLK_DIV - 1));
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 4'h0;
            shift_reg <= 8'h0;
            clk_cnt <= 4'h0;
            busy_r <= 1'b0;
            done_r <= 1'b0;
            sclk_r <= 1'b0;
            mosi_r <= 1'b0;
            cs_n_r <= 1'b1;
        end else begin
            done_r <= 1'b0;  // default to 0
            
            case (state)
                IDLE: begin
                    busy_r <= 1'b0;
                    cs_n_r <= 1'b1;
                    sclk_r <= 1'b0;
                    if (start) begin
                        state <= START;
                        shift_reg <= tx_data;
                        bit_cnt <= 4'h0;
                        clk_cnt <= 4'h0;
                        busy_r <= 1'b1;
                    end
                end
                
                START: begin
                    cs_n_r <= 1'b0;
                    sclk_r <= 1'b0;
                    if (clk_en) begin
                        state <= TX_RX;
                        clk_cnt <= 4'h0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                TX_RX: begin
                    if (clk_en) begin
                        if (bit_cnt < 8) begin
                            // On rising edge of sclk, sample miso
                            if (sclk_r == 1'b0) begin
                                sclk_r <= 1'b1;
                                mosi_r <= shift_reg[7];
                            end else begin
                                sclk_r <= 1'b0;
                                shift_reg <= {shift_reg[6:0], miso};
                                bit_cnt <= bit_cnt + 1'b1;
                            end
                        end else begin
                            state <= END;
                            clk_cnt <= 4'h0;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                END: begin
                    sclk_r <= 1'b0;
                    cs_n_r <= 1'b1;
                    if (clk_en) begin
                        state <= IDLE;
                        busy_r <= 1'b0;
                        done_r <= 1'b1;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    assign rx_data = shift_reg;

endmodule
