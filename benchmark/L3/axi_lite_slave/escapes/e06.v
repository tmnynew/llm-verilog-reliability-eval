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
    reg aw_pending;

    // 写数据通道状态
    reg w_done;
    reg [31:0] w_data_reg;
    reg [3:0] w_strb_reg;
    reg w_pending;

    // 写响应通道状态
    reg bvalid_reg;
    reg [1:0] bresp_reg;

    // 读地址通道状态
    reg ar_done;
    reg [7:0] ar_addr_reg;
    reg ar_pending;

    // 读数据通道状态
    reg rvalid_reg;
    reg [31:0] rdata_reg;
    reg [1:0] rresp_reg;

    // 地址译码函数
    wire [1:0] aw_reg_sel = aw_addr_reg[3:2];
    wire aw_unmapped = (aw_addr_reg[7:4] != 4'h0);
    wire aw_is_id = (aw_addr_reg[3:0] == 4'hC);

    wire [1:0] ar_reg_sel = ar_addr_reg[3:2];
    wire ar_unmapped = (ar_addr_reg[7:4] != 4'h0);
    wire ar_is_id = (ar_addr_reg[3:0] == 4'hC);

    // AW通道握手
    assign awready = !aw_pending;
    always @(posedge clk) begin
        if (!rst_n) begin
            aw_pending <= 1'b0;
            aw_done <= 1'b0;
            aw_addr_reg <= 8'h0;
        end else begin
            if (awvalid && awready && !aw_pending) begin
                aw_pending <= 1'b1;
                aw_done <= 1'b1;
                aw_addr_reg <= awaddr;
            end else if (aw_pending && w_done) begin
                aw_pending <= 1'b0;
                aw_done <= 1'b0;
            end
        end
    end

    // W通道握手
    assign wready = !w_pending;
    always @(posedge clk) begin
        if (!rst_n) begin
            w_pending <= 1'b0;
            w_done <= 1'b0;
            w_data_reg <= 32'h0;
            w_strb_reg <= 4'h0;
        end else begin
            if (wvalid && wready && !w_pending) begin
                w_pending <= 1'b1;
                w_done <= 1'b1;
                w_data_reg <= wdata;
                w_strb_reg <= wstrb;
            end else if (w_pending && aw_done) begin
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
        end else begin
            if (aw_done && w_done && !bvalid_reg) begin
                bvalid_reg <= 1'b1;
                if (aw_unmapped)
                    bresp_reg <= 2'b11; // DECERR
                else if (aw_is_id)
                    bresp_reg <= 2'b10; // SLVERR
                else
                    bresp_reg <= 2'b00; // OKAY
            end else if (bvalid_reg && bready) begin
                bvalid_reg <= 1'b0;
            end
        end
    end

    // 写数据到寄存器
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            REG0 <= 32'h0;
            REG1 <= 32'h0;
            REG2 <= 32'h0;
        end else begin
            if (aw_done && w_done && !bvalid_reg) begin
                if (!aw_unmapped && !aw_is_id) begin
                    case (aw_reg_sel)
                        2'b00: begin
                            for (i = 0; i < 4; i = i + 1) begin
                                if (w_strb_reg[i])
                                    REG0[i*8 +: 8] <= w_data_reg[i*8 +: 8];
                            end
                        end
                        2'b01: begin
                            for (i = 0; i < 4; i = i + 1) begin
                                if (w_strb_reg[i])
                                    REG1[i*8 +: 8] <= w_data_reg[i*8 +: 8];
                            end
                        end
                        2'b10: begin
                            for (i = 0; i < 4; i = i + 1) begin
                                if (w_strb_reg[i])
                                    REG2[i*8 +: 8] <= w_data_reg[i*8 +: 8];
                            end
                        end
                        default: ;
                    endcase
                end
            end
        end
    end

    // AR通道握手
    assign arready = !ar_pending;
    always @(posedge clk) begin
        if (!rst_n) begin
            ar_pending <= 1'b0;
            ar_done <= 1'b0;
            ar_addr_reg <= 8'h0;
        end else begin
            if (arvalid && arready && !ar_pending) begin
                ar_pending <= 1'b1;
                ar_done <= 1'b1;
                ar_addr_reg <= araddr;
            end else if (ar_pending && rvalid_reg && rready) begin
                ar_pending <= 1'b0;
                ar_done <= 1'b0;
            end
        end
    end

    // 读数据生成
    always @(posedge clk) begin
        if (!rst_n) begin
            rvalid_reg <= 1'b0;
            rdata_reg <= 32'h0;
            rresp_reg <= 2'b00;
        end else begin
            if (ar_done && !rvalid_reg) begin
                rvalid_reg <= 1'b1;
                if (ar_unmapped) begin
                    rdata_reg <= 32'h0;
                    rresp_reg <= 2'b11; // DECERR
                end else if (ar_is_id) begin
                    rdata_reg <= ID;
                    rresp_reg <= 2'b00; // OKAY
                end else begin
                    case (ar_reg_sel)
                        2'b00: rdata_reg <= REG0;
                        2'b01: rdata_reg <= REG1;
                        2'b10: rdata_reg <= REG2;
                        default: rdata_reg <= 32'h0;
                    endcase
                    rresp_reg <= 2'b00; // OKAY
                end
            end else if (rvalid_reg && rready) begin
                rvalid_reg <= 1'b0;
            end
        end
    end

    assign bvalid = bvalid_reg;
    assign bresp = bresp_reg;
    assign rvalid = rvalid_reg;
    assign rdata = rdata_reg;
    assign rresp = rresp_reg;

endmodule
