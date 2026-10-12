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

    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] tx_reg;
    reg [7:0] rx_reg;
    reg [3:0] clk_cnt;
    reg busy_r;
    reg done_r;
    reg sclk_r;
    reg mosi_r;
    reg cs_n_r;

    parameter IDLE = 4'b0000;
    parameter START_SETUP = 4'b0001;
    parameter TRANSFER = 4'b0010;
    parameter END_CYCLE = 4'b0011;

    assign busy = busy_r;
    assign done = done_r;
    assign sclk = sclk_r;
    assign mosi = mosi_r;
    assign cs_n = cs_n_r;
    assign rx_data = rx_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 0;
            tx_reg <= 0;
            rx_reg <= 0;
            clk_cnt <= 0;
            busy_r <= 0;
            done_r <= 0;
            sclk_r <= 0;
            mosi_r <= 0;
            cs_n_r <= 1;
        end else begin
            case (state)
                IDLE: begin
                    done_r <= 0;
                    if (start && !busy_r) begin
                        busy_r <= 1;
                        tx_reg <= tx_data;
                        bit_cnt <= 0;
                        clk_cnt <= 0;
                        cs_n_r <= 0;
                        mosi_r <= tx_data[7];
                        state <= START_SETUP;
                    end
                end

                START_SETUP: begin
                    if (clk_cnt < CLK_DIV - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        sclk_r <= ~sclk_r;
                        state <= TRANSFER;
                    end
                end

                TRANSFER: begin
                    if (sclk_r == 0) begin // Falling edge of sclk - update MOSI
                        if (bit_cnt < 7) begin
                            bit_cnt <= bit_cnt + 1;
                            mosi_r <= tx_reg[6-bit_cnt];
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                            mosi_r <= tx_reg[6-bit_cnt]; // This is actually bit 0, so next will be invalid
                        end
                        sclk_r <= ~sclk_r;
                    end else begin // Rising edge of sclk - sample MISO
                        rx_reg[7-bit_cnt] <= miso;
                        if (bit_cnt == 7) begin
                            sclk_r <= 0;
                            cs_n_r <= 1;
                            state <= END_CYCLE;
                        end else begin
                            sclk_r <= ~sclk_r;
                        end
                    end
                end

                END_CYCLE: begin
                    done_r <= 1;
                    state <= IDLE;
                    busy_r <= 0;
                end

                default: begin
                    state <= IDLE;
                    done_r <= 0;
                    busy_r <= 0;
                end
            endcase

            if (!rst_n) begin
                state <= IDLE;
                bit_cnt <= 0;
                tx_reg <= 0;
                rx_reg <= 0;
                clk_cnt <= 0;
                busy_r <= 0;
                done_r <= 0;
                sclk_r <= 0;
                mosi_r <= 0;
                cs_n_r <= 1;
            end
        end
    end

endmodule
