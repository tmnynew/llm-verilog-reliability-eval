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

    reg [1:0] sclk_sync, cs_n_sync, mosi_sync;
    reg sclk_pos_edge, sclk_neg_edge, cs_n_neg_edge;
    reg [2:0] bit_cnt;
    reg [7:0] tx_shift_reg, rx_shift_reg;
    reg [7:0] rx_data_reg;
    reg miso_reg, rx_valid_reg;
    reg cs_n_prev;
    
    // Synchronization
    always @(posedge clk) begin
        sclk_sync <= {sclk_sync[0], sclk};
        cs_n_sync <= {cs_n_sync[0], cs_n};
        mosi_sync <= {mosi_sync[0], mosi};
        
        sclk_pos_edge <= (sclk_sync == 2'b01);
        sclk_neg_edge <= (sclk_sync == 2'b10);
        cs_n_neg_edge <= (cs_n_sync == 2'b10);
        
        cs_n_prev <= cs_n_sync[1];
    end
    
    // Bit counter and shift registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 3'b000;
            tx_shift_reg <= 8'h00;
            rx_shift_reg <= 8'h00;
            rx_data_reg <= 8'h00;
            miso_reg <= 1'b0;
            rx_valid_reg <= 1'b0;
        end else begin
            rx_valid_reg <= 1'b0;
            
            // Detect CS falling edge to start transaction
            if (cs_n_neg_edge) begin
                tx_shift_reg <= tx_data;
                bit_cnt <= 3'b000;
                rx_shift_reg <= 8'h00;
                miso_reg <= tx_data[7];  // Output MSB after 1-2 cycles
            end 
            // Continue only when CS is low
            else if (!cs_n_sync[1]) begin
                // On SCLK rising edge - sample MOSI (receive)
                if (sclk_pos_edge) begin
                    rx_shift_reg <= {rx_shift_reg[6:0], mosi_sync[1]};
                    bit_cnt <= bit_cnt + 1'b1;
                    
                    // After receiving 8 bits
                    if (bit_cnt == 3'd7) begin
                        rx_data_reg <= {rx_shift_reg[6:0], mosi_sync[1]};
                        rx_valid_reg <= 1'b1;
                        bit_cnt <= 3'b000;  // Ready for next byte
                        rx_shift_reg <= 8'h00;
                        
                        // Update MISO to 0 after sending last bit
                        miso_reg <= 1'b0;
                    end
                end
                // On SCLK falling edge - update MISO (transmit next bit)
                else if (sclk_neg_edge) begin
                    if (bit_cnt < 3'd7) begin
                        miso_reg <= tx_shift_reg[~bit_cnt];  // Next bit to send
                    end
                end
            end
            // When CS goes high, reset state
            else if (cs_n_sync[1] && !cs_n_prev) begin
                miso_reg <= 1'b0;
                bit_cnt <= 3'b000;
            end
            // If CS is high, ensure MISO is 0
            else if (cs_n_sync[1]) begin
                miso_reg <= 1'b0;
            end
        end
    end

    assign miso = miso_reg;
    assign rx_data = rx_data_reg;
    assign rx_valid = rx_valid_reg;

endmodule
