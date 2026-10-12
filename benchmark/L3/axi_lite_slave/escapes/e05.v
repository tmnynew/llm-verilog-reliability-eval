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

// Internal signals
reg [31:0] reg0, reg1, reg2;
reg [31:0] id_reg;
reg [1:0] bresp_reg;
reg bvalid_reg;
reg rvalid_reg;
reg [31:0] rdata_reg;
reg [1:0] rresp_reg;

// State machine for write response
reg [1:0] wr_state;
reg [1:0] rd_state;

// Write address and data handshake
reg awready_reg;
reg wready_reg;
reg [31:0] wr_data;
reg [3:0] wr_strb;
reg [7:0] wr_addr;

// Read address handshake
reg arready_reg;

// Write response control
reg bvalid_pulse;
reg rvalid_pulse;

// Register write logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reg0 <= 32'h00000000;
        reg1 <= 32'h00000000;
        reg2 <= 32'h00000000;
        id_reg <= 32'h5A5A0003;
        bvalid_reg <= 1'b0;
        rvalid_reg <= 1'b0;
        bresp_reg <= 2'b00;
        rresp_reg <= 2'b00;
        rdata_reg <= 32'h00000000;
        wr_state <= 2'b00;
        rd_state <= 2'b00;
        awready_reg <= 1'b0;
        wready_reg <= 1'b0;
        arready_reg <= 1'b0;
        bvalid_pulse <= 1'b0;
        rvalid_pulse <= 1'b0;
    end else begin
        // Write address channel
        if (awvalid && awready_reg) begin
            wr_addr <= awaddr;
        end

        // Write data channel
        if (wvalid && wready_reg) begin
            wr_data <= wdata;
            wr_strb <= wstrb;
        end

        // Write state machine
        case (wr_state)
            2'b00: begin
                if (awvalid && awready_reg && wvalid && wready_reg) begin
                    wr_state <= 2'b01;
                end else if (awvalid && awready_reg) begin
                    wr_state <= 2'b10;
                end else if (wvalid && wready_reg) begin
                    wr_state <= 2'b11;
                end
            end
            2'b01: begin
                wr_state <= 2'b00;
            end
            2'b10: begin
                if (wvalid && wready_reg) begin
                    wr_state <= 2'b01;
                end
            end
            2'b11: begin
                if (awvalid && awready_reg) begin
                    wr_state <= 2'b01;
                end
            end
        endcase

        // Read state machine
        case (rd_state)
            2'b00: begin
                if (arvalid && arready_reg) begin
                    rd_state <= 2'b01;
                end
            end
            2'b01: begin
                rd_state <= 2'b00;
            end
        endcase

        // Write register logic
        if (wr_state == 2'b01) begin
            case (wr_addr[3:2])
                2'b00: begin
                    if (wr_strb[0]) reg0[7:0] <= wr_data[7:0];
                    if (wr_strb[1]) reg0[15:8] <= wr_data[15:8];
                    if (wr_strb[2]) reg0[23:16] <= wr_data[23:16];
                    if (wr_strb[3]) reg0[31:24] <= wr_data[31:24];
                end
                2'b01: begin
                    if (wr_strb[0]) reg1[7:0] <= wr_data[7:0];
                    if (wr_strb[1]) reg1[15:8] <= wr_data[15:8];
                    if (wr_strb[2]) reg1[23:16] <= wr_data[23:16];
                    if (wr_strb[3]) reg1[31:24] <= wr_data[31:24];
                end
                2'b10: begin
                    if (wr_strb[0]) reg2[7:0] <= wr_data[7:0];
                    if (wr_strb[1]) reg2[15:8] <= wr_data[15:8];
                    if (wr_strb[2]) reg2[23:16] <= wr_data[23:16];
                    if (wr_strb[3]) reg2[31:24] <= wr_data[31:24];
                end
                2'b11: begin
                    // Do not write to ID register
                end
            endcase
        end

        // Write response logic
        if (wr_state == 2'b01) begin
            if (wr_addr[3:2] == 2'b11) begin
                bresp_reg <= 2'b10; // SLVERR
            end else if (wr_addr[7:4] != 4'b0000) begin
                bresp_reg <= 2'b11; // DECERR
            end else begin
                bresp_reg <= 2'b00; // OKAY
            end
            bvalid_reg <= 1'b1;
            bvalid_pulse <= 1'b1;
        end else if (bvalid_pulse && bready) begin
            bvalid_reg <= 1'b0;
            bvalid_pulse <= 1'b0;
        end

        // Read data logic
        if (rd_state == 2'b01) begin
            case (araddr[3:2])
                2'b00: rdata_reg <= reg0;
                2'b01: rdata_reg <= reg1;
                2'b10: rdata_reg <= reg2;
                2'b11: rdata_reg <= id_reg;
                default: rdata_reg <= 32'h00000000;
            endcase

            if (araddr[7:4] != 4'b0000) begin
                rresp_reg <= 2'b11; // DECERR
                rdata_reg <= 32'h00000000;
            end else begin
                rresp_reg <= 2'b00; // OKAY
            end

            rvalid_reg <= 1'b1;
            rvalid_pulse <= 1'b1;
        end else if (rvalid_pulse && rready) begin
            rvalid_reg <= 1'b0;
            rvalid_pulse <= 1'b0;
        end
    end
end

// Output assignments
assign awready = awready_reg;
assign wready = wready_reg;
assign arready = arready_reg;
assign bvalid = bvalid_reg;
assign bresp = bresp_reg;
assign rvalid = rvalid_reg;
assign rdata = rdata_reg;
assign rresp = rresp_reg;

// Ready control logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        awready_reg <= 1'b0;
        wready_reg <= 1'b0;
        arready_reg <= 1'b0;
    end else begin
        if (awvalid && !awready_reg) begin
            awready_reg <= 1'b1;
        end else if (awvalid && awready_reg && wr_state == 2'b01) begin
            awready_reg <= 1'b0;
        end

        if (wvalid && !wready_reg) begin
            wready_reg <= 1'b1;
        end else if (wvalid && wready_reg && wr_state == 2'b01) begin
            wready_reg <= 1'b0;
        end

        if (arvalid && !arready_reg) begin
            arready_reg <= 1'b1;
        end else if (arvalid && arready_reg && rd_state == 2'b01) begin
            arready_reg <= 1'b0;
        end
    end
end

endmodule
