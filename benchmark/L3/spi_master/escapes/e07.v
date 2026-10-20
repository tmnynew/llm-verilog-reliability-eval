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
    reg [7:0] rx_shift_reg;
    reg [3:0] clk_div_cnt;
    reg sclk_reg;
    reg mosi_reg;
    reg cs_n_reg;
    reg busy_reg;
    reg done_reg;

    // State definitions
    parameter IDLE = 3'b000;
    parameter START = 3'b001;
    parameter TRANSMIT = 3'b010;
    parameter WAIT_HALF = 3'b011;
    parameter SAMPLE = 3'b100;
    parameter FINISH = 3'b101;

    assign rx_data = rx_shift_reg;
    assign busy = busy_reg;
    assign done = done_reg;
    assign sclk = sclk_reg;
    assign mosi = mosi_reg;
    assign cs_n = cs_n_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 0;
            shift_reg <= 0;
            rx_shift_reg <= 0;
            clk_div_cnt <= 0;
            sclk_reg <= 0;
            mosi_reg <= 0;
            cs_n_reg <= 1;
            busy_reg <= 0;
            done_reg <= 0;
        end else begin
            done_reg <= 0;
            
            case (state)
                IDLE: begin
                    busy_reg <= 0;
                    cs_n_reg <= 1;
                    sclk_reg <= 0;
                    if (start) begin
                        state <= START;
                        shift_reg <= tx_data;
                        rx_shift_reg <= 0;
                        bit_cnt <= 0;
                        clk_div_cnt <= 0;
                        busy_reg <= 1;
                    end
                end
                
                START: begin
                    cs_n_reg <= 0;
                    mosi_reg <= shift_reg[7];
                    sclk_reg <= 0;
                    clk_div_cnt <= 0;
                    state <= TRANSMIT;
                end
                
                TRANSMIT: begin
                    if (clk_div_cnt < CLK_DIV - 1) begin
                        clk_div_cnt <= clk_div_cnt + 1;
                    end else begin
                        clk_div_cnt <= 0;
                        sclk_reg <= 1;  // Rising edge to latch data on slave
                        state <= WAIT_HALF;
                    end
                end
                
                WAIT_HALF: begin
                    if (clk_div_cnt < CLK_DIV - 1) begin
                        clk_div_cnt <= clk_div_cnt + 1;
                    end else begin
                        clk_div_cnt <= 0;
                        rx_shift_reg <= {rx_shift_reg[6:0], miso};
                        sclk_reg <= 0;  // Falling edge
                        bit_cnt <= bit_cnt + 1;
                        
                        if (bit_cnt == 7) begin
                            state <= FINISH;
                        end else begin
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            mosi_reg <= shift_reg[6];  // Next bit
                            state <= TRANSMIT;
                        end
                    end
                end
                
                FINISH: begin
                    cs_n_reg <= 1;
                    busy_reg <= 0;
                    done_reg <= 1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
