module axi_lite_slave (
    input clk,
    input rst_n,
    input awvalid,
    input [7:0] awaddr,
    output awready,
    input wvalid,
    input [31:0] wdata,
    input [3:0] wstrb,
    output wready,
    output bvalid,
    output [1:0] bresp,
    input bready,
    input arvalid,
    input [7:0] araddr,
    output arready,
    output rvalid,
    output [31:0] rdata,
    output [1:0] rresp,
    input rready
);

    // 寄存器
    reg [31:0] REG0, REG1, REG2;
    wire [31:0] ID = 32'h5A5A_0003;

    // 写地址通道状态
    reg aw_done;
    reg [7:0] awaddr_reg;
    reg aw_pending;

    // 写数据通道状态
    reg w_done;
    reg [31:0] wdata_reg;
    reg [3:0] wstrb_reg;
    reg w_pending;

    // 写响应通道状态
    reg bvalid_reg;
    reg [1:0] bresp_reg;
    reg [1:0] b_timer;

    // 读地址通道状态
    reg ar_done;
    reg [7:0] araddr_reg;
    reg ar_pending;

    // 读数据通道状态
    reg rvalid_reg;
    reg [31:0] rdata_reg;
    reg [1:0] rresp_reg;
    reg [1:0] r_timer;

    // 地址译码函数
    wire [3:0] aw_high = awaddr[7:4];
    wire [1:0] aw_sel = awaddr[3:2];
    wire [3:0] ar_high = araddr[7:4];
    wire [1:0] ar_sel = araddr[3:2];

    // awready: 当没有未完成的写地址事务时接受
    assign awready = !aw_pending;

    // wready: 当没有未完成的写数据事务时接受
    assign wready = !w_pending;

    // arready: 当没有未完成的读地址事务时接受
    assign arready = !ar_pending;

    // 写地址通道握手
    always @(posedge clk) begin
        if (!rst_n) begin
            aw_pending <= 1'b0;
            aw_done <= 1'b0;
            awaddr_reg <= 8'b0;
        end else begin
            if (awvalid && awready) begin
                aw_pending <= 1'b1;
                aw_done <= 1'b1;
                awaddr_reg <= awaddr;
            end else if (aw_done && w_done) begin
                aw_pending <= 1'b0;
                aw_done <= 1'b0;
            end
        end
    end

    // 写数据通道握手
    always @(posedge clk) begin
        if (!rst_n) begin
            w_pending <= 1'b0;
            w_done <= 1'b0;
            wdata_reg <= 32'b0;
            wstrb_reg <= 4'b0;
        end else begin
            if (wvalid && wready) begin
                w_pending <= 1'b1;
                w_done <= 1'b1;
                wdata_reg <= wdata;
                wstrb_reg <= wstrb;
            end else if (aw_done && w_done) begin
                w_pending <= 1'b0;
                w_done <= 1'b0;
            end
        end
    end

    // 写响应生成
    always @(posedge clk) begin
        if (!rst_n) begin
            bvalid_reg <= 1'b0;
            bresp_reg <= 2'b00;
            b_timer <= 2'b00;
        end else begin
            if (bvalid_reg && bready) begin
                bvalid_reg <= 1'b0;
            end else if (aw_done && w_done && !bvalid_reg) begin
                // 地址译码
                if (aw_high != 4'b0000) begin
                    bresp_reg <= 2'b11; // DECERR
                end else if (aw_sel == 2'b11) begin
                    bresp_reg <= 2'b10; // SLVERR
                end else begin
                    bresp_reg <= 2'b00; // OKAY
                    // 写入寄存器
                    if (aw_sel == 2'b00) begin
                        if (wstrb_reg[0]) REG0[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) REG0[15:8] <= wdata_reg[15:8];
                        if (wstrb_reg[2]) REG0[23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) REG0[31:24] <= wdata_reg[31:24];
                    end else if (aw_sel == 2'b01) begin
                        if (wstrb_reg[0]) REG1[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) REG1[15:8] <= wdata_reg[15:8];
                        if (wstrb_reg[2]) REG1[23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) REG1[31:24] <= wdata_reg[31:24];
                    end else if (aw_sel == 2'b10) begin
                        if (wstrb_reg[0]) REG2[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) REG2[15:8] <= wdata_reg[15:8];
                        if (wstrb_reg[2]) REG2[23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) REG2[31:24] <= wdata_reg[31:24];
                    end
                end
                bvalid_reg <= 1'b1;
                b_timer <= 2'b00;
            end else if (aw_done && w_done && bvalid_reg) begin
                // 等待 bready
                b_timer <= b_timer + 1'b1;
            end
        end
    end

    // 读地址通道握手
    always @(posedge clk) begin
        if (!rst_n) begin
            ar_pending <= 1'b0;
            ar_done <= 1'b0;
            araddr_reg <= 8'b0;
        end else begin
            if (arvalid && arready) begin
                ar_pending <= 1'b1;
                ar_done <= 1'b1;
                araddr_reg <= araddr;
            end else if (ar_done && rvalid_reg && rready) begin
                ar_pending <= 1'b0;
                ar_done <= 1'b0;
            end
        end
    end

    // 读数据生成
    always @(posedge clk) begin
        if (!rst_n) begin
            rvalid_reg <= 1'b0;
            rdata_reg <= 32'b0;
            rresp_reg <= 2'b00;
            r_timer <= 2'b00;
        end else begin
            if (rvalid_reg && rready) begin
                rvalid_reg <= 1'b0;
            end else if (ar_done && !rvalid_reg) begin
                // 地址译码
                if (ar_high != 4'b0000) begin
                    rdata_reg <= 32'b0;
                    rresp_reg <= 2'b11; // DECERR
                end else begin
                    rresp_reg <= 2'b00; // OKAY
                    case (ar_sel)
                        2'b00: rdata_reg <= REG0;
                        2'b01: rdata_reg <= REG1;
                        2'b10: rdata_reg <= REG2;
                        2'b11: rdata_reg <= ID;
                    endcase
                end
                rvalid_reg <= 1'b1;
                r_timer <= 2'b00;
            end else if (ar_done && rvalid_reg) begin
                r_timer <= r_timer + 1'b1;
            end
        end
    end

    // 寄存器复位
    always @(posedge clk) begin
        if (!rst_n) begin
            REG0 <= 32'b0;
            REG1 <= 32'b0;
            REG2 <= 32'b0;
        end
    end

    assign bvalid = bvalid_reg;
    assign bresp = bresp_reg;
    assign rvalid = rvalid_reg;
    assign rdata = rdata_reg;
    assign rresp = rresp_reg;

endmodule
