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

    reg [7:0] rdata_r;
    reg busy_r;
    reg done_r;
    reg ack_err_r;
    reg scl_o_r;
    reg sda_o_r;

    assign rdata = rdata_r;
    assign busy = busy_r;
    assign done = done_r;
    assign ack_err = ack_err_r;
    assign scl_o = scl_o_r;
    assign sda_o = sda_o_r;

    // Clock divider and phase counter
    reg [7:0] clk_div_cnt;
    reg [1:0] phase;  // 0: low-update, 1: high-rise, 2: high-sample, 3: low-fall
    reg [6:0] clk_div_max;
    
    // State machine
    parameter IDLE = 0, START = 1, ADDR_TX = 2, ADDR_ACK = 3, 
              WRITE_DATA = 4, WRITE_ACK = 5, READ_DATA = 6, 
              READ_ACK = 7, STOP = 8;
    reg [3:0] state;
    
    // Bit transmission
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg [7:0] temp_rdata;
    reg [6:0] addr_reg;
    reg rw_reg;
    reg [7:0] wdata_reg;
    reg sample_sda_next;
    reg [7:0] sample_sda_delayed;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div_cnt <= 8'h00;
            phase <= 2'b00;
            clk_div_max <= CLK_DIV - 1;
            
            state <= IDLE;
            bit_cnt <= 4'h0;
            shift_reg <= 8'h00;
            temp_rdata <= 8'h00;
            addr_reg <= 7'h00;
            rw_reg <= 1'b0;
            wdata_reg <= 8'h00;
            
            busy_r <= 1'b0;
            done_r <= 1'b0;
            ack_err_r <= 1'b0;
            scl_o_r <= 1'b1;
            sda_o_r <= 1'b1;
            rdata_r <= 8'h00;
            sample_sda_delayed <= 8'h00;
        end else begin
            sample_sda_delayed <= {sample_sda_delayed[6:0], sda_i};
            
            // Clock division logic
            if (clk_div_cnt == clk_div_max) begin
                clk_div_cnt <= 8'h00;
                
                case (phase)
                    2'b00: begin  // Phase 0: SCL low, update SDA
                        phase <= 2'b01;
                        case (state)
                            START: sda_o_r <= 1'b0;  // Start condition
                            ADDR_TX, WRITE_DATA: sda_o_r <= shift_reg[7];
                            ADDR_ACK, WRITE_ACK: sda_o_r <= 1'b1;  // Release for ACK
                            READ_DATA: sda_o_r <= 1'b1;  // Release for reading
                            READ_ACK: sda_o_r <= 1'b1;  // Send NACK
                            STOP: sda_o_r <= 1'b0;  // Prepare for stop
                        endcase
                    end
                    2'b01: begin  // Phase 1: SCL rise
                        phase <= 2'b10;
                        scl_o_r <= 1'b1;
                    end
                    2'b10: begin  // Phase 2: SCL high, sample SDA
                        phase <= 2'b11;
                        sample_sda_next <= 1'b1;
                        
                        if (state == READ_DATA) begin
                            temp_rdata <= {temp_rdata[6:0], sda_i};
                        end
                    end
                    2'b11: begin  // Phase 3: SCL fall
                        phase <= 2'b00;
                        scl_o_r <= 1'b0;
                        sample_sda_next <= 1'b0;
                        
                        if (state == STOP && bit_cnt == 4'd1) begin
                            // End of stop sequence
                            done_r <= 1'b1;
                            busy_r <= 1'b0;
                            scl_o_r <= 1'b1;
                            sda_o_r <= 1'b1;
                            state <= IDLE;
                            bit_cnt <= 4'h0;
                        end else if (state != IDLE) begin
                            bit_cnt <= bit_cnt + 1'b1;
                            
                            case (state)
                                START: begin
                                    if (bit_cnt == 4'd0) begin
                                        bit_cnt <= 4'h0;
                                        if (rw_reg == 1'b0) begin
                                            state <= ADDR_TX;
                                            shift_reg <= {addr_reg, 1'b0};  // Address + write bit
                                        end else begin
                                            state <= ADDR_TX;
                                            shift_reg <= {addr_reg, 1'b1};  // Address + read bit
                                        end
                                    end
                                end
                                
                                ADDR_TX: begin
                                    if (bit_cnt == 4'd7) begin  // After sending 8 bits
                                        bit_cnt <= 4'h0;
                                        shift_reg <= {shift_reg[6:0], 1'b0};
                                        state <= ADDR_ACK;
                                    end else begin
                                        shift_reg <= {shift_reg[6:0], 1'b0};
                                    end
                                end
                                
                                ADDR_ACK: begin
                                    if (bit_cnt == 4'd0) begin
                                        bit_cnt <= 4'h0;
                                        if (sda_i == 1'b1) begin  // NACK received
                                            ack_err_r <= 1'b1;
                                            if (rw_reg == 1'b0) begin
                                                state <= STOP;
                                                bit_cnt <= 4'h0;
                                            end else begin
                                                state <= STOP;
                                                bit_cnt <= 4'h0;
                                            end
                                        end else begin  // ACK received
                                            if (rw_reg == 1'b0) begin
                                                state <= WRITE_DATA;
                                                shift_reg <= wdata_reg;
                                                bit_cnt <= 4'h0;
                                            end else begin
                                                state <= READ_DATA;
                                                bit_cnt <= 4'h0;
                                                temp_rdata <= 8'h00;
                                            end
                                        end
                                    end
                                end
                                
                                WRITE_DATA: begin
                                    if (bit_cnt == 4'd7) begin  // After sending 8 bits
                                        bit_cnt <= 4'h0;
                                        shift_reg <= {shift_reg[6:0], 1'b0};
                                        state <= WRITE_ACK;
                                    end else begin
                                        shift_reg <= {shift_reg[6:0], 1'b0};
                                    end
                                end
                                
                                WRITE_ACK: begin
                                    if (bit_cnt == 4'd0) begin
                                        bit_cnt <= 4'h0;
                                        if (sda_i == 1'b1) begin  // NACK received
                                            ack_err_r <= 1'b1;
                                        end
                                        state <= STOP;
                                    end
                                end
                                
                                READ_DATA: begin
                                    if (bit_cnt == 4'd7) begin  // After receiving 8 bits
                                        bit_cnt <= 4'h0;
                                        rdata_r <= temp_rdata;
                                        state <= READ_ACK;
                                    end
                                end
                                
                                READ_ACK: begin
                                    if (bit_cnt == 4'd0) begin
                                        bit_cnt <= 4'h0;
                                        state <= STOP;
                                    end
                                end
                                
                                STOP: begin
                                    if (bit_cnt == 4'd1) begin
                                        // Will be handled in next cycle's phase 3
                                    end else if (bit_cnt == 4'd0) begin
                                        sda_o_r <= 1'b1;  // Complete stop condition
                                    end
                                end
                            endcase
                        end
                    end
                endcase
            end else begin
                clk_div_cnt <= clk_div_cnt + 1'b1;
            end
            
            // Handle start signal
            if (!busy_r && start) begin
                busy_r <= 1'b1;
                done_r <= 1'b0;
                ack_err_r <= 1'b0;
                addr_reg <= addr;
                rw_reg <= rw;
                wdata_reg <= wdata;
                state <= START;
                bit_cnt <= 4'h0;
                phase <= 2'b00;
                clk_div_cnt <= 8'h00;
                scl_o_r <= 1'b1;
                sda_o_r <= 1'b1;
            end
            
            // Done pulse only lasts one cycle
            if (done_r)
                done_r <= 1'b0;
                
            // Reset handling during transaction
            if (!rst_n) begin
                busy_r <= 1'b0;
                scl_o_r <= 1'b1;
                sda_o_r <= 1'b1;
            end
        end
    end

endmodule
