module sync_fifo #(parameter DW = 8, parameter DEPTH = 16) (
    input clk,
    input rst_n,
    input wr_en,
    input [DW-1:0] wr_data,
    input rd_en,
    output reg [DW-1:0] rd_data,
    output reg full,
    output reg empty,
    output reg [4:0] count
);

    // 内部存储
    reg [DW-1:0] mem [0:DEPTH-1];
    
    // 指针
    reg [4:0] wr_ptr;
    reg [4:0] rd_ptr;
    
    // 读写接受标志
    wire wr_acc;
    wire rd_acc;
    
    assign wr_acc = wr_en & ~full;
    assign rd_acc = rd_en & ~empty;
    
    integer i;
    
    always @(posedge clk) begin
        if (~rst_n) begin
            // 同步复位
            wr_ptr <= 5'd0;
            rd_ptr <= 5'd0;
            count <= 5'd0;
            full <= 1'b0;
            empty <= 1'b1;
            rd_data <= {DW{1'b0}};
        end else begin
            // 写操作
            if (wr_acc) begin
                mem[wr_ptr[4:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            
            // 读操作
            if (rd_acc) begin
                rd_data <= mem[rd_ptr[4:0]];
                rd_ptr <= rd_ptr + 1'b1;
            end
            
            // 更新计数器
            case ({wr_acc, rd_acc})
                2'b10: count <= count + 1'b1;  // 只写
                2'b01: count <= count - 1'b1;  // 只读
                default: count <= count;        // 同时读写或不操作
            endcase
            
            // 更新标志
            empty <= (count == 5'd0);
            full <= (count == DEPTH[4:0]);
        end
    end

endmodule
