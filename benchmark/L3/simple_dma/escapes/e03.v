module simple_dma (
    input clk,
    input rst_n,
    input start,
    input [7:0] src,
    input [7:0] dst,
    input [7:0] len,
    output busy,
    output done,
    output [7:0] mem_addr,
    output [7:0] mem_wdata,
    output mem_we,
    output mem_re,
    input [7:0] mem_rdata
);

    // State machine states
    parameter IDLE = 2'b00;
    parameter READ = 2'b01;
    parameter WRITE = 2'b10;
    
    reg [1:0] state;
    reg [7:0] current_src;
    reg [7:0] current_dst;
    reg [8:0] counter;  // Use 9-bit to count up to 256
    reg done_reg;
    
    assign busy = (state != IDLE) | done_reg;
    assign done = done_reg;
    
    // Memory interface signals
    assign mem_addr = (state == READ) ? current_src : current_dst;
    assign mem_wdata = mem_rdata;
    assign mem_we = (state == WRITE);
    assign mem_re = (state == READ);
    
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            current_src <= 8'h00;
            current_dst <= 8'h00;
            counter <= 9'h000;
            done_reg <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= READ;
                        current_src <= src;
                        current_dst <= dst;
                        counter <= 9'h000;
                        done_reg <= 1'b0;
                    end else begin
                        done_reg <= 1'b0;
                    end
                end
                
                READ: begin
                    state <= WRITE;
                end
                
                WRITE: begin
                    if (counter < len - 1) begin
                        state <= READ;
                        current_src <= current_src + 1;
                        current_dst <= current_dst + 1;
                        counter <= counter + 1;
                    end else begin
                        state <= IDLE;
                        done_reg <= 1'b1;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
