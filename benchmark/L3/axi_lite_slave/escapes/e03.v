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

    reg [1:0] write_state; // 00: idle, 01: got aw, 10: got w, 11: both ready
    reg [2:0] write_delay;
    reg [2:0] read_delay;
    reg [31:0] reg0, reg1, reg2;
    reg [31:0] read_data_reg;
    reg [1:0] read_resp_reg;
    reg [1:0] write_resp_reg;
    reg bvalid_reg;
    reg rvalid_reg;

    assign awready = (write_state == 2'b00) || (write_state == 2'b01);
    assign wready = (write_state == 2'b00) || (write_state == 2'b10);
    assign arready = (read_delay == 0);
    assign bvalid = bvalid_reg;
    assign bresp = write_resp_reg;
    assign rvalid = rvalid_reg;
    assign rdata = read_data_reg;
    assign rresp = read_resp_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            write_state <= 2'b00;
            write_delay <= 0;
            read_delay <= 0;
            reg0 <= 0;
            reg1 <= 0;
            reg2 <= 0;
            bvalid_reg <= 0;
            rvalid_reg <= 0;
            read_data_reg <= 0;
            read_resp_reg <= 2'b00;
            write_resp_reg <= 2'b00;
        end else begin
            // Write state machine
            case (write_state)
                2'b00: begin
                    if (awvalid && awready) write_state <= 2'b01;
                    if (wvalid && wready) write_state <= 2'b10;
                    if (awvalid && awready && wvalid && wready) write_state <= 2'b11;
                end
                2'b01: begin
                    if (wvalid && wready) write_state <= 2'b11;
                end
                2'b10: begin
                    if (awvalid && awready) write_state <= 2'b11;
                end
                2'b11: begin
                    write_state <= 2'b00;
                end
            endcase

            // Handle write transaction completion
            if (awvalid && awready && wvalid && wready) begin
                // Process write
                if (awaddr[7:4] != 4'h0) begin
                    write_resp_reg <= 2'b11; // DECERR
                end else if (awaddr[3:2] == 3) begin
                    write_resp_reg <= 2'b10; // SLVERR for ID register
                end else begin
                    write_resp_reg <= 2'b00; // OKAY
                    if (wstrb[0]) begin
                        case (awaddr[3:2])
                            2'b00: reg0[7:0] <= wdata[7:0];
                            2'b01: reg1[7:0] <= wdata[7:0];
                            2'b10: reg2[7:0] <= wdata[7:0];
                        endcase
                    end
                    if (wstrb[1]) begin
                        case (awaddr[3:2])
                            2'b00: reg0[15:8] <= wdata[15:8];
                            2'b01: reg1[15:8] <= wdata[15:8];
                            2'b10: reg2[15:8] <= wdata[15:8];
                        endcase
                    end
                    if (wstrb[2]) begin
                        case (awaddr[3:2])
                            2'b00: reg0[23:16] <= wdata[23:16];
                            2'b01: reg1[23:16] <= wdata[23:16];
                            2'b10: reg2[23:16] <= wdata[23:16];
                        endcase
                    end
                    if (wstrb[3]) begin
                        case (awaddr[3:2])
                            2'b00: reg0[31:24] <= wdata[31:24];
                            2'b01: reg1[31:24] <= wdata[31:24];
                            2'b10: reg2[31:24] <= wdata[31:24];
                        endcase
                    end
                end
                write_delay <= 1; // Start delay counter for write response
            end else if (write_delay > 0 && write_delay < 5) begin
                write_delay <= write_delay + 1;
            end

            // Generate write response when delay is done
            if (write_delay >= 1 && write_delay <= 4) begin
                bvalid_reg <= 1;
            end
            if (bready && bvalid_reg) begin
                bvalid_reg <= 0;
                write_delay <= 0;
            end

            // Handle read transaction
            if (arvalid && arready) begin
                if (araddr[7:4] != 4'h0) begin
                    read_resp_reg <= 2'b11; // DECERR
                    read_data_reg <= 0;
                end else begin
                    case (araddr[3:2])
                        2'b00: read_data_reg <= reg0;
                        2'b01: read_data_reg <= reg1;
                        2'b10: read_data_reg <= reg2;
                        2'b11: read_data_reg <= 32'h5A5A0003; // ID register
                    endcase
                    read_resp_reg <= 2'b00; // OKAY
                end
                read_delay <= 1; // Start delay counter for read response
            end else if (read_delay > 0 && read_delay < 5) begin
                read_delay <= read_delay + 1;
            end

            // Generate read response when delay is done
            if (read_delay >= 1 && read_delay <= 4) begin
                rvalid_reg <= 1;
            end
            if (rready && rvalid_reg) begin
                rvalid_reg <= 0;
                read_delay <= 0;
            end
        end
    end

endmodule
