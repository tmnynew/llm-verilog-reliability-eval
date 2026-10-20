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

    reg [2:0] state;
    reg [7:0] cnt;
    reg [7:0] current_src;
    reg [7:0] current_dst;
    reg [8:0] next_cnt;
    reg [9:0] next_src;
    reg [9:0] next_dst;
    reg done_reg;
    
    parameter IDLE = 3'b000;
    parameter READ = 3'b001;
    parameter WRITE = 3'b010;
    parameter DONE_PULSE = 3'b011;

    assign busy = (state != IDLE);
    assign done = done_reg;
    assign mem_addr = (state == READ) ? current_src : current_dst;
    assign mem_wdata = mem_rdata;
    assign mem_we = (state == WRITE);
    assign mem_re = (state == READ);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cnt <= 8'h00;
            current_src <= 8'h00;
            current_dst <= 8'h00;
            done_reg <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= READ;
                        cnt <= len;
                        current_src <= src;
                        current_dst <= dst;
                        done_reg <= 1'b0;
                    end else begin
                        done_reg <= 1'b0;
                    end
                end
                
                READ: begin
                    state <= WRITE;
                end
                
                WRITE: begin
                    if (cnt == 1) begin
                        state <= DONE_PULSE;
                    end else begin
                        state <= READ;
                        current_src <= current_src + 1;
                        current_dst <= current_dst + 1;
                        cnt <= cnt - 1;
                    end
                end
                
                DONE_PULSE: begin
                    state <= IDLE;
                    done_reg <= 1'b1;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
