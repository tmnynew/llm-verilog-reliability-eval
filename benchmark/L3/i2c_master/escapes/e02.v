module i2c_master #(parameter CLK_DIV = 4) (
    input clk,
    input rst_n,
    input start,
    input rw,
    input [6:0] addr,
    input [7:0] wdata,
    output [7:0] rdata,
    output busy,
    output done,
    output ack_err,
    output scl_o,
    output sda_o,
    input sda_i
);

    reg [6:0] addr_reg;
    reg rw_reg;
    reg [7:0] wdata_reg;
    reg [7:0] rdata_reg;
    reg busy_reg;
    reg done_reg;
    reg ack_err_reg;
    reg scl_o_reg;
    reg sda_o_reg;
    
    // Clock divider counter
    reg [$clog2(CLK_DIV):0] clk_cnt;
    // Phase counter (0-3)
    reg [1:0] phase;
    // Bit counter for data transmission/reception
    reg [3:0] bit_cnt;
    // State machine
    reg [3:0] state;
    
    // States
    parameter IDLE = 4'd0;
    parameter START = 4'd1;
    parameter ADDR_TX = 4'd2;
    parameter ADDR_ACK_RX = 4'd3;
    parameter DATA_TX = 4'd4;
    parameter DATA_ACK_RX = 4'd5;
    parameter DATA_RX = 4'd6;
    parameter DATA_NACK_TX = 4'd7;
    parameter STOP = 4'd8;
    
    assign rdata = rdata_reg;
    assign busy = busy_reg;
    assign done = done_reg;
    assign ack_err = ack_err_reg;
    assign scl_o = scl_o_reg;
    assign sda_o = sda_o_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            clk_cnt <= 0;
            phase <= 0;
            bit_cnt <= 0;
            state <= IDLE;
            
            addr_reg <= 0;
            rw_reg <= 0;
            wdata_reg <= 0;
            rdata_reg <= 0;
            busy_reg <= 0;
            done_reg <= 0;
            ack_err_reg <= 0;
            scl_o_reg <= 1;
            sda_o_reg <= 1;
        end else begin
            done_reg <= 0;  // Default to 0, only 1 cycle pulse
            
            if (clk_cnt < CLK_DIV - 1) begin
                clk_cnt <= clk_cnt + 1;
            end else begin
                clk_cnt <= 0;
                
                if (phase == 3) begin
                    phase <= 0;
                end else begin
                    phase <= phase + 1;
                end
                
                case (phase)
                    2'b00: begin  // Update SDA when SCL is low
                        case (state)
                            IDLE: begin
                                if (start && !busy_reg) begin
                                    addr_reg <= addr;
                                    rw_reg <= rw;
                                    wdata_reg <= wdata;
                                    ack_err_reg <= 0;
                                    busy_reg <= 1;
                                    state <= START;
                                    sda_o_reg <= 0;  // Start condition
                                end
                            end
                            
                            START: begin
                                sda_o_reg <= addr_reg[6];  // First bit of address
                                bit_cnt <= 0;
                                state <= ADDR_TX;
                            end
                            
                            ADDR_TX: begin
                                if (bit_cnt < 7) begin
                                    sda_o_reg <= addr_reg[6-bit_cnt];
                                end else begin
                                    sda_o_reg <= rw_reg;  // R/W bit
                                end
                            end
                            
                            ADDR_ACK_RX: begin
                                sda_o_reg <= 1;  // Release SDA to read ACK
                            end
                            
                            DATA_TX: begin
                                sda_o_reg <= wdata_reg[7-bit_cnt];
                            end
                            
                            DATA_ACK_RX: begin
                                sda_o_reg <= 1;  // Release SDA to read ACK
                            end
                            
                            DATA_RX: begin
                                sda_o_reg <= 1;  // Release SDA for reading
                            end
                            
                            DATA_NACK_TX: begin
                                sda_o_reg <= 1;  // Send NACK
                            end
                            
                            STOP: begin
                                sda_o_reg <= 0;  // Pull SDA low first
                            end
                        endcase
                    end
                    
                    2'b01: begin  // SCL rising edge
                        scl_o_reg <= 1;
                    end
                    
                    2'b10: begin  // Sample SDA when SCL is high
                        case (state)
                            ADDR_ACK_RX: begin
                                if (sda_i) begin  // NACK received
                                    ack_err_reg <= 1;
                                    state <= STOP;
                                end else begin  // ACK received
                                    if (rw_reg) begin  // Read transaction
                                        state <= DATA_RX;
                                        bit_cnt <= 0;
                                    end else begin  // Write transaction
                                        state <= DATA_TX;
                                        bit_cnt <= 0;
                                    end
                                end
                            end
                            
                            DATA_TX: begin
                                if (bit_cnt < 7) begin
                                    bit_cnt <= bit_cnt + 1;
                                end else begin
                                    state <= DATA_ACK_RX;
                                end
                            end
                            
                            DATA_ACK_RX: begin
                                if (sda_i) begin  // NACK received in write
                                    ack_err_reg <= 1;
                                end
                                state <= STOP;
                            end
                            
                            DATA_RX: begin
                                rdata_reg[7-bit_cnt] <= sda_i;
                                if (bit_cnt < 7) begin
                                    bit_cnt <= bit_cnt + 1;
                                end else begin
                                    state <= DATA_NACK_TX;
                                end
                            end
                        endcase
                    end
                    
                    2'b11: begin  // SCL falling edge
                        scl_o_reg <= 0;
                        
                        case (state)
                            ADDR_TX: begin
                                if (bit_cnt < 7) begin
                                    bit_cnt <= bit_cnt + 1;
                                end else begin
                                    state <= ADDR_ACK_RX;
                                end
                            end
                            
                            DATA_TX: begin
                                if (bit_cnt < 7) begin
                                    // Stay in DATA_TX, handled in phase 2
                                end else begin
                                    // Handled in phase 2
                                end
                            end
                            
                            DATA_RX: begin
                                if (bit_cnt < 7) begin
                                    // Stay in DATA_RX, handled in phase 2
                                end else begin
                                    // Handled in phase 2
                                end
                            end
                            
                            DATA_NACK_TX: begin
                                state <= STOP;
                            end
                            
                            STOP: begin
                                sda_o_reg <= 1;  // Release SDA
                                state <= IDLE;
                                busy_reg <= 0;
                                done_reg <= 1;
                            end
                        endcase
                    end
                endcase
            end
        end
    end

endmodule
