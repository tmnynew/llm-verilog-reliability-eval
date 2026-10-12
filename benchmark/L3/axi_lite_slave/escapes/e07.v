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
    reg [1:0] b_resp_pending;
    reg b_pending;

    // 读地址通道状态
    reg ar_done;
    reg [7:0] araddr_reg;
    reg ar_pending;

    // 读数据通道状态
    reg rvalid_reg;
    reg [31:0] rdata_reg;
    reg [1:0] rresp_reg;
    reg [1:0] r_resp_pending;
    reg r_pending;

    // 地址译码函数
    function [1:0] decode_addr;
        input [7:0] addr;
        begin
            if (addr[7:4] != 4'h0)
                decode_addr = 2'b11; // DECERR
            else if (addr[3:2] == 2'b11)
                decode_addr = 2'b10; // SLVERR (ID register, read-only)
            else
                decode_addr = 2'b00; // OKAY
        end
    endfunction

    // 写地址通道
    assign awready = !aw_pending || aw_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            aw_done <= 1'b0;
            awaddr_reg <= 8'h0;
            aw_pending <= 1'b0;
        end else begin
            if (awvalid && awready && !aw_done) begin
                awaddr_reg <= awaddr;
                aw_done <= 1'b1;
                aw_pending <= 1'b1;
            end
            if (aw_done && w_done) begin
                aw_done <= 1'b0;
                aw_pending <= 1'b0;
            end
        end
    end

    // 写数据通道
    assign wready = !w_pending || w_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            w_done <= 1'b0;
            wdata_reg <= 32'h0;
            wstrb_reg <= 4'h0;
            w_pending <= 1'b0;
        end else begin
            if (wvalid && wready && !w_done) begin
                wdata_reg <= wdata;
                wstrb_reg <= wstrb;
                w_done <= 1'b1;
                w_pending <= 1'b1;
            end
            if (aw_done && w_done) begin
                w_done <= 1'b0;
                w_pending <= 1'b0;
            end
        end
    end

    // 写响应通道
    assign bvalid = bvalid_reg;
    assign bresp = bresp_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            bvalid_reg <= 1'b0;
            bresp_reg <= 2'b00;
            b_resp_pending <= 2'b00;
            b_pending <= 1'b0;
        end else begin
            if (aw_done && w_done && !b_pending) begin
                // 执行写操作
                case (awaddr_reg[3:2])
                    2'b00: begin
                        if (wstrb_reg[0]) REG0[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) REG0[15:8] <= wdata_reg[15:8];
                        if (wstrb_reg[2]) REG0[23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) REG0[31:24] <= wdata_reg[31:24];
                        b_resp_pending <= 2'b00;
                    end
                    2'b01: begin
                        if (wstrb_reg[0]) REG1[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) REG1[15:8] <= wdata_reg[15:8];
                        if (wstrb_reg[2]) REG1[23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) REG1[31:24] <= wdata_reg[31:24];
                        b_resp_pending <= 2'b00;
                    end
                    2'b10: begin
                        if (wstrb_reg[0]) REG2[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) REG2[15:8] <= wdata_reg[15:8];
                        if (wstrb_reg[2]) REG2[23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) REG2[31:24] <= wdata_reg[31:24];
                        b_resp_pending <= 2'b00;
                    end
                    2'b11: begin
                        b_resp_pending <= 2'b10; // SLVERR
                    end
                endcase
                if (awaddr_reg[7:4] != 4'h0)
                    b_resp_pending <= 2'b11; // DECERR
                b_pending <= 1'b1;
            end
            if (b_pending && !bvalid_reg) begin
                bvalid_reg <= 1'b1;
                bresp_reg <= b_resp_pending;
            end
            if (bvalid_reg && bready) begin
                bvalid_reg <= 1'b0;
                b_pending <= 1'b0;
            end
        end
    end

    // 读地址通道
    assign arready = !ar_pending || ar_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            ar_done <= 1'b0;
            araddr_reg <= 8'h0;
            ar_pending <= 1'b0;
        end else begin
            if (arvalid && arready && !ar_done) begin
                araddr_reg <= araddr;
                ar_done <= 1'b1;
                ar_pending <= 1'b1;
            end
            if (ar_done && rvalid_reg && rready) begin
                ar_done <= 1'b0;
                ar_pending <= 1'b0;
            end
        end
    end

    // 读数据通道
    assign rvalid = rvalid_reg;
    assign rdata = rdata_reg;
    assign rresp = rresp_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            rvalid_reg <= 1'b0;
            rdata_reg <= 32'h0;
            rresp_reg <= 2'b00;
            r_resp_pending <= 2'b00;
            r_pending <= 1'b0;
        end else begin
            if (ar_done && !r_pending) begin
                case (araddr_reg[3:2])
                    2'b00: begin
                        rdata_reg <= REG0;
                        r_resp_pending <= 2'b00;
                    end
                    2'b01: begin
                        rdata_reg <= REG1;
                        r_resp_pending <= 2'b00;
                    end
                    2'b10: begin
                        rdata_reg <= REG2;
                        r_resp_pending <= 2'b00;
                    end
                    2'b11: begin
                        rdata_reg <= ID;
                        r_resp_pending <= 2'b00;
                    end
                endcase
                if (araddr_reg[7:4] != 4'h0) begin
                    rdata_reg <= 32'h0;
                    r_resp_pending <= 2'b11; // DECERR
                end
                r_pending <= 1'b1;
            end
            if (r_pending && !rvalid_reg) begin
                rvalid_reg <= 1'b1;
                rresp_reg <= r_resp_pending;
            end
            if (rvalid_reg && rready) begin
                rvalid_reg <= 1'b0;
                r_pending <= 1'b0;
            end
        end
    end

endmodule
