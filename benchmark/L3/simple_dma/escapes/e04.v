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

    parameter IDLE = 2'b00;
    parameter READ = 2'b01;
    parameter WRITE = 2'b10;

    reg [1:0] state, next_state;
    reg [7:0] src_idx, next_src_idx;
    reg [7:0] dst_idx, next_dst_idx;
    reg [7:0] cnt, next_cnt;
    reg done_reg, next_done_reg;
    
    // 状态转移
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            src_idx <= 8'h00;
            dst_idx <= 8'h00;
            cnt <= 8'h00;
            done_reg <= 1'b0;
        end else begin
            state <= next_state;
            src_idx <= next_src_idx;
            dst_idx <= next_dst_idx;
            cnt <= next_cnt;
            done_reg <= next_done_reg;
        end
    end
    
    // 组合逻辑
    always @(*) begin
        next_state = state;
        next_src_idx = src_idx;
        next_dst_idx = dst_idx;
        next_cnt = cnt;
        next_done_reg = 1'b0;
        
        case (state)
            IDLE: begin
                if (start) begin
                    next_state = READ;
                    next_src_idx = src;
                    next_dst_idx = dst;
                    next_cnt = len;
                end
            end
            
            READ: begin
                next_state = WRITE;
            end
            
            WRITE: begin
                if (cnt == 8'h01) begin
                    next_state = IDLE;
                    next_done_reg = 1'b1;
                end else begin
                    next_state = READ;
                    next_src_idx = src_idx + 8'h01;
                    next_dst_idx = dst_idx + 8'h01;
                    next_cnt = cnt - 8'h01;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // 输出逻辑
    assign busy = (state != IDLE);
    assign done = done_reg;
    
    assign mem_addr = (state == READ) ? src_idx : dst_idx;
    assign mem_wdata = mem_rdata;
    assign mem_we = (state == WRITE);
    assign mem_re = (state == READ);

endmodule
