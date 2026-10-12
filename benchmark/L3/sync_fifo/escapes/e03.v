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

    // 内部存储器
    reg [DW-1:0] mem [0:DEPTH-1];
    
    // 读写指针
    reg [4:0] wr_ptr;
    reg [4:0] rd_ptr;
    
    // 实际使用的指针位宽
    localparam PTR_W = 5; // 足够覆盖 DEPTH=16 的情况
    
    integer i;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            // 同步复位
            wr_ptr <= 0;
            rd_ptr <= 0;
            count <= 0;
            full <= 0;
            empty <= 1;
            rd_data <= 0;
        end else begin
            // 判断读写是否被接受
            // 写被接受: wr_en && !full
            // 读被接受: rd_en && !empty
            
            if (wr_en && !full) begin
                // 写入数据
                mem[wr_ptr[PTR_W-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end
            
            if (rd_en && !empty) begin
                // 读出数据
                rd_data <= mem[rd_ptr[PTR_W-1:0]];
                rd_ptr <= rd_ptr + 1;
            end
            
            // 更新 count
            if (wr_en && !full && !(rd_en && !empty)) begin
                // 只写不读
                count <= count + 1;
            end else if (!(wr_en && !full) && rd_en && !empty) begin
                // 只读不写
                count <= count - 1;
            end
            // 同时读写或都不操作时 count 不变
            
            // 更新标志
            if (wr_en && !full && !(rd_en && !empty)) begin
                // 只写不读
                if (count + 1 == DEPTH) begin
                    full <= 1;
                end
                empty <= 0;
            end else if (!(wr_en && !full) && rd_en && !empty) begin
                // 只读不写
                if (count - 1 == 0) begin
                    empty <= 1;
                end
                full <= 0;
            end else if (wr_en && !full && rd_en && !empty) begin
                // 同时读写
                // count 不变，full 和 empty 也不变
                // 但如果 count == DEPTH-1 且同时读写，full 保持 0
                // 如果 count == 1 且同时读写，empty 保持 0
                // 这些情况已经由上面的条件处理
            end
        end
    end

endmodule
