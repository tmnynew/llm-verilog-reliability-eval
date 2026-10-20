module sync_fifo #(parameter DW = 8, parameter DEPTH = 16) (
    input clk,
    input rst_n,
    input wr_en,
    input [7:0] wr_data,
    input rd_en,
    output [7:0] rd_data,
    output full,
    output empty,
    output [4:0] count
);

    // 定义地址宽度
    localparam ADDR_WIDTH = $clog2(DEPTH);

    // 存储数组
    reg [DW-1:0] mem [0:DEPTH-1];

    // 读写指针
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    // 计数器
    reg [ADDR_WIDTH:0] cnt;

    // 标志信号
    wire full_flag;
    wire empty_flag;

    // 临时变量
    reg [DW-1:0] rd_data_reg;
    reg [ADDR_WIDTH:0] cnt_next;
    reg [ADDR_WIDTH-1:0] wr_ptr_next;
    reg [ADDR_WIDTH-1:0] rd_ptr_next;

    // 满标志：计数器等于深度
    assign full_flag = (cnt == DEPTH);
    // 空标志：计数器为0
    assign empty_flag = (cnt == 0);

    // 输出赋值
    assign full = full_flag;
    assign empty = empty_flag;
    assign count = cnt;

    // 读数据寄存器更新逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_data_reg <= 0;
        else if (rd_en && !empty_flag)
            rd_data_reg <= mem[rd_ptr];
    end

    assign rd_data = rd_data_reg;

    // 指针和计数器更新逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            cnt <= 0;
        end else begin
            // 更新写指针和计数器
            if (wr_en && !full_flag) begin
                wr_ptr <= wr_ptr_next;
                cnt <= cnt_next;
            end

            // 更新读指针和计数器
            if (rd_en && !empty_flag) begin
                rd_ptr <= rd_ptr_next;
                cnt <= cnt_next;
            end
        end
    end

    // 下一状态计算
    always @(*) begin
        cnt_next = cnt;
        wr_ptr_next = wr_ptr;
        rd_ptr_next = rd_ptr;

        if (wr_en && !full_flag) begin
            wr_ptr_next = (wr_ptr == DEPTH - 1) ? 0 : wr_ptr + 1;
            cnt_next = cnt + 1;
        end

        if (rd_en && !empty_flag) begin
            rd_ptr_next = (rd_ptr == DEPTH - 1) ? 0 : rd_ptr + 1;
            cnt_next = cnt - 1;
        end
    end

    // 写入操作
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 无需初始化内存内容
        end else if (wr_en && !full_flag) begin
            mem[wr_ptr] <= wr_data;
        end
    end

endmodule
