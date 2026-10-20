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

    reg [3:0] state;
    reg [3:0] cnt;
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;
    reg busy_r;
    reg done_r;
    reg ack_err_r;
    reg scl_o_r;
    reg sda_o_r;
    
    parameter IDLE = 4'b0000;
    parameter START = 4'b0001;
    parameter ADDR = 4'b0010;
    parameter ADDR_ACK = 4'b0011;
    parameter WRITE_DATA = 4'b0100;
    parameter WRITE_ACK = 4'b0101;
    parameter READ_DATA = 4'b0110;
    parameter READ_ACK = 4'b0111;
    parameter STOP = 4'b1000;
    
    assign busy = busy_r;
    assign done = done_r;
    assign ack_err = ack_err_r;
    assign scl_o = scl_o_r;
    assign sda_o = sda_o_r;
    assign rdata = shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cnt <= 0;
            bit_cnt <= 0;
            shift_reg <= 0;
            busy_r <= 0;
            done_r <= 0;
            ack_err_r <= 0;
            scl_o_r <= 1;
            sda_o_r <= 1;
        end else begin
            done_r <= 0;
            
            case (state)
                IDLE: begin
                    if (start) begin
                        busy_r <= 1;
                        state <= START;
                        cnt <= 0;
                        scl_o_r <= 1;
                        sda_o_r <= 1;
                    end
                end
                
                START: begin
                    cnt <= cnt + 1;
                    if (cnt == CLK_DIV - 1) begin
                        sda_o_r <= 0; // SDA falls while SCL high
                    end else if (cnt == 2 * CLK_DIV - 1) begin
                        scl_o_r <= 0; // SCL falls
                        state <= ADDR;
                        cnt <= 0;
                        shift_reg <= {addr, rw};
                        bit_cnt <= 0;
                    end
                end
                
                ADDR: begin
                    cnt <= cnt + 1;
                    if (cnt == 0) begin
                        sda_o_r <= shift_reg[7];
                    end else if (cnt == CLK_DIV - 1) begin
                        scl_o_r <= 1; // SCL rises
                    end else if (cnt == 2 * CLK_DIV - 1) begin
                        scl_o_r <= 0; // SCL falls
                        shift_reg <= shift_reg << 1;
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 7) begin
                            state <= ADDR_ACK;
                            cnt <= 0;
                            sda_o_r <= 1; // Release SDA for ACK
                        end else begin
                            cnt <= 0;
                        end
                    end
                end
                
                ADDR_ACK: begin
                    cnt <= cnt + 1;
                    if (cnt == CLK_DIV - 1) begin
                        scl_o_r <= 1; // SCL rises
                    end else if (cnt == 2 * CLK_DIV - 1) begin
                        scl_o_r <= 0; // SCL falls
                        if (sda_i) begin // No ACK received
                            ack_err_r <= 1;
                            state <= STOP;
                            cnt <= 0;
                        end else if (rw) begin // Read operation
                            state <= READ_DATA;
                            cnt <= 0;
                            bit_cnt <= 0;
                            shift_reg <= 0;
                        end else begin // Write operation
                            state <= WRITE_DATA;
                            cnt <= 0;
                            shift_reg <= wdata;
                            bit_cnt <= 0;
                        end
                    end
                end
                
                WRITE_DATA: begin
                    cnt <= cnt + 1;
                    if (cnt == 0) begin
                        sda_o_r <= shift_reg[7];
                    end else if (cnt == CLK_DIV - 1) begin
                        scl_o_r <= 1; // SCL rises
                    end else if (cnt == 2 * CLK_DIV - 1) begin
                        scl_o_r <= 0; // SCL falls
                        shift_reg <= shift_reg << 1;
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 7) begin
                            state <= WRITE_ACK;
                            cnt <= 0;
                            sda_o_r <= 1; // Release SDA for ACK
                        end else begin
                            cnt <= 0;
                        end
                    end
                end
                
                WRITE_ACK: begin
                    cnt <= cnt + 1;
                    if (cnt == CLK_DIV - 1) begin
                        scl_o_r <= 1; // SCL rises
                    end else if (cnt == 2 * CLK_DIV - 1) begin
                        scl_o_r <= 0; // SCL falls
                        if (sda_i) begin // No ACK received
                            ack_err_r <= 1;
                        end
                        state <= STOP;
                        cnt <= 0;
                    end
                end
                
                READ_DATA: begin
                    cnt <= cnt + 1;
                    if (cnt == CLK_DIV - 1) begin
                        scl_o_r <= 1; // SCL rises
                        shift_reg <= {shift_reg[6:0], sda_i}; // Sample on rising edge
                    end else if (cnt == 2 * CLK_DIV - 1) begin
                        scl_o_r <= 0; // SCL falls
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 7) begin
                            state <= READ_ACK;
                            cnt <= 0;
                            sda_o_r <= 1; // Send NACK
                        end else begin
                            cnt <= 0;
                        end
                    end
                end
                
                READ_ACK: begin
                    cnt <= cnt + 1;
                    if (cnt == 0) begin
                        sda_o_r <= 1; // Send NACK
                    end else if (cnt == CLK_DIV - 1) begin
                        scl_o_r <= 1; // SCL rises
                    end else if (cnt == 2 * CLK_DIV - 1) begin
                        scl_o_r <= 0; // SCL falls
                        state <= STOP;
                        cnt <= 0;
                    end
                end
                
                STOP: begin
                    cnt <= cnt + 1;
                    if (cnt == 0) begin
                        sda_o_r <= 0; // Keep SDA low
                    end else if (cnt == CLK_DIV - 1) begin
                        scl_o_r <= 1; // SCL rises
                    end else if (cnt == 2 * CLK_DIV - 1) begin
                        sda_o_r <= 1; // SDA rises while SCL high
                        busy_r <= 0;
                        done_r <= 1;
                        state <= IDLE;
                        cnt <= 0;
                    end
                end
                
            endcase
        end
    end

endmodule
