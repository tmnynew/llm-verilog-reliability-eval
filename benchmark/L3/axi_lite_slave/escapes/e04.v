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
    localparam [31:0] ID = 32'h5A5A_0003;

    // 写地址通道状态
    reg aw_done;
    reg [7:0] aw_addr_reg;
    reg [1:0] aw_resp;

    // 写数据通道状态
    reg w_done;
    reg [31:0] w_data_reg;
    reg [3:0] w_strb_reg;

    // 写响应通道
    reg bvalid_reg;
    reg [1:0] bresp_reg;

    // 读地址通道状态
    reg ar_done;
    reg [7:0] ar_addr_reg;
    reg [1:0] ar_resp;

    // 读数据通道
    reg rvalid_reg;
    reg [31:0] rdata_reg;
    reg [1:0] rresp_reg;

    // 写响应定时器（最多4周期）
    reg [1:0] b_timer;
    // 读响应定时器（最多4周期）
    reg [1:0] r_timer;

    // 地址译码函数
    function [1:0] decode_addr;
        input [7:0] addr;
        begin
            if (addr[7:4] != 4'h0)
                decode_addr = 2'b11; // DECERR
            else if (addr[3:2] == 2'b11)
                decode_addr = 2'b10; // SLVERR (写) 或 OKAY (读，但由外部处理)
            else
                decode_addr = 2'b00; // OKAY
        end
    endfunction

    // 写地址握手
    assign awready = !aw_done;
    always @(posedge clk) begin
        if (!rst_n) begin
            aw_done <= 1'b0;
            aw_addr_reg <= 8'h0;
            aw_resp <= 2'b00;
        end else begin
            if (awvalid && awready && !aw_done) begin
                aw_done <= 1'b1;
                aw_addr_reg <= awaddr;
                aw_resp <= decode_addr(awaddr);
            end
            if (aw_done && w_done && bvalid_reg && bready) begin
                aw_done <= 1'b0;
            end
        end
    end

    // 写数据握手
    assign wready = !w_done;
    always @(posedge clk) begin
        if (!rst_n) begin
            w_done <= 1'b0;
            w_data_reg <= 32'h0;
            w_strb_reg <= 4'h0;
        end else begin
            if (wvalid && wready && !w_done) begin
                w_done <= 1'b1;
                w_data_reg <= wdata;
                w_strb_reg <= wstrb;
            end
            if (aw_done && w_done && bvalid_reg && bready) begin
                w_done <= 1'b0;
            end
        end
    end

    // 写响应
    always @(posedge clk) begin
        if (!rst_n) begin
            bvalid_reg <= 1'b0;
            bresp_reg <= 2'b00;
            b_timer <= 2'd0;
        end else begin
            if (bvalid_reg && bready) begin
                bvalid_reg <= 1'b0;
            end
            if (aw_done && w_done && !bvalid_reg) begin
                if (b_timer < 2'd3) begin
                    b_timer <= b_timer + 1'b1;
                end else begin
                    bvalid_reg <= 1'b1;
                    bresp_reg <= aw_resp;
                    b_timer <= 2'd0;
                    // 执行写操作
                    if (aw_resp == 2'b00) begin
                        case (aw_addr_reg[3:2])
                            2'b00: begin
                                if (w_strb_reg[0]) REG0[7:0] <= w_data_reg[7:0];
                                if (w_strb_reg[1]) REG0[15:8] <= w_data_reg[15:8];
                                if (w_strb_reg[2]) REG0[23:16] <= w_data_reg[23:16];
                                if (w_strb_reg[3]) REG0[31:24] <= w_data_reg[31:24];
                            end
                            2'b01: begin
                                if (w_strb_reg[0]) REG1[7:0] <= w_data_reg[7:0];
                                if (w_strb_reg[1]) REG1[15:8] <= w_data_reg[15:8];
                                if (w_strb_reg[2]) REG1[23:16] <= w_data_reg[23:16];
                                if (w_strb_reg[3]) REG1[31:24] <= w_data_reg[31:24];
                            end
                            2'b10: begin
                                if (w_strb_reg[0]) REG2[7:0] <= w_data_reg[7:0];
                                if (w_strb_reg[1]) REG2[15:8] <= w_data_reg[15:8];
                                if (w_strb_reg[2]) REG2[23:16] <= w_data_reg[23:16];
                                if (w_strb_reg[3]) REG2[31:24] <= w_data_reg[31:24];
                            end
                            default: ;
                        endcase
                    end
                end
            end
            if (!aw_done || !w_done) begin
                b_timer <= 2'd0;
            end
        end
    end

    assign bvalid = bvalid_reg;
    assign bresp = bresp_reg;

    // 读地址握手
    assign arready = !ar_done;
    always @(posedge clk) begin
        if (!rst_n) begin
            ar_done <= 1'b0;
            ar_addr_reg <= 8'h0;
            ar_resp <= 2'b00;
        end else begin
            if (arvalid && arready && !ar_done) begin
                ar_done <= 1'b1;
                ar_addr_reg <= araddr;
                if (araddr[7:4] != 4'h0)
                    ar_resp <= 2'b11; // DECERR
                else
                    ar_resp <= 2'b00; // OKAY
            end
            if (ar_done && rvalid_reg && rready) begin
                ar_done <= 1'b0;
            end
        end
    end

    // 读数据
    always @(posedge clk) begin
        if (!rst_n) begin
            rvalid_reg <= 1'b0;
            rdata_reg <= 32'h0;
            rresp_reg <= 2'b00;
            r_timer <= 2'd0;
        end else begin
            if (rvalid_reg && rready) begin
                rvalid_reg <= 1'b0;
            end
            if (ar_done && !rvalid_reg) begin
                if (r_timer < 2'd3) begin
                    r_timer <= r_timer + 1'b1;
                end else begin
                    rvalid_reg <= 1'b1;
                    rresp_reg <= ar_resp;
                    r_timer <= 2'd0;
                    if (ar_resp == 2'b00) begin
                        case (ar_addr_reg[3:2])
                            2'b00: rdata_reg <= REG0;
                            2'b01: rdata_reg <= REG1;
                            2'b10: rdata_reg <= REG2;
                            2'b11: rdata_reg <= ID;
                            default: rdata_reg <= 32'h0;
                        endcase
                    end else begin
                        rdata_reg <= 32'h0;
                    end
                end
            end
            if (!ar_done) begin
                r_timer <= 2'd0;
            end
        end
    end

    assign rvalid = rvalid_reg;
    assign rdata = rdata_reg;
    assign rresp = rresp_reg;

    // 寄存器复位
    always @(posedge clk) begin
        if (!rst_n) begin
            REG0 <= 32'h0;
            REG1 <= 32'h0;
            REG2 <= 32'h0;
        end
    end

endmodule
