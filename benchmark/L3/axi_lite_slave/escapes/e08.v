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

    // Register addresses
    parameter REG0_ADDR = 8'h00;
    parameter REG1_ADDR = 8'h04;
    parameter REG2_ADDR = 8'h08;
    parameter ID_ADDR   = 8'h0C;
    
    // Response codes
    parameter RESP_OKAY   = 2'b00;
    parameter RESP_SLVERR = 2'b10;
    parameter RESP_DECERR = 2'b11;
    
    // Internal signals for write transaction
    reg write_transaction_pending;
    reg [7:0] write_addr_reg;
    reg [31:0] write_data_reg;
    reg [3:0] write_strb_reg;
    reg [1:0] write_resp_reg;
    reg [2:0] write_resp_delay_counter;
    
    // Internal signals for read transaction
    reg read_transaction_pending;
    reg [7:0] read_addr_reg;
    reg [1:0] read_resp_reg;
    reg [2:0] read_resp_delay_counter;
    
    // Registers
    reg [31:0] reg0, reg1, reg2;
    
    // Write response channel
    reg bvalid_reg;
    reg [1:0] bresp_reg;
    
    // Read response channel
    reg rvalid_reg;
    reg [31:0] rdata_reg;
    reg [1:0] rresp_reg;
    
    // AW and W handshake control
    assign awready = !write_transaction_pending || (awvalid && wvalid && !bvalid_reg);
    assign wready = !write_transaction_pending || (awvalid && wvalid && !bvalid_reg);
    
    // AR handshake control
    assign arready = !read_transaction_pending || (arvalid && !rvalid_reg);
    
    // Output assignments
    assign bvalid = bvalid_reg;
    assign bresp = bresp_reg;
    assign rvalid = rvalid_reg;
    assign rdata = rdata_reg;
    assign rresp = rresp_reg;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            reg0 <= 32'h00000000;
            reg1 <= 32'h00000000;
            reg2 <= 32'h00000000;
            
            write_transaction_pending <= 1'b0;
            write_addr_reg <= 8'h00;
            write_data_reg <= 32'h00000000;
            write_strb_reg <= 4'h0;
            write_resp_reg <= RESP_OKAY;
            write_resp_delay_counter <= 3'd0;
            
            read_transaction_pending <= 1'b0;
            read_addr_reg <= 8'h00;
            read_resp_reg <= RESP_OKAY;
            read_resp_delay_counter <= 3'd0;
            
            bvalid_reg <= 1'b0;
            bresp_reg <= RESP_OKAY;
            
            rvalid_reg <= 1'b0;
            rdata_reg <= 32'h00000000;
            rresp_reg <= RESP_OKAY;
        end else begin
            // Handle write address and data channels
            if (awvalid && awready) begin
                write_addr_reg <= awaddr;
            end
            
            if (wvalid && wready) begin
                write_data_reg <= wdata;
                write_strb_reg <= wstrb;
            end
            
            // Start write transaction when both AW and W are received
            if (awvalid && awready && wvalid && wready) begin
                write_transaction_pending <= 1'b1;
                write_resp_delay_counter <= 3'd0;
                
                // Determine response based on address
                if (awaddr[7:4] != 4'h0) begin
                    write_resp_reg <= RESP_DECERR;
                end else if (awaddr == ID_ADDR) begin
                    write_resp_reg <= RESP_SLVERR;
                end else begin
                    write_resp_reg <= RESP_OKAY;
                end
            end
            
            // Process write transaction after delay
            if (write_transaction_pending) begin
                write_resp_delay_counter <= write_resp_delay_counter + 1'b1;
                
                // Execute write at the right time
                if (write_resp_delay_counter == 3'd3) begin
                    // Only write if address is valid and not ID register
                    if (write_addr_reg[7:4] == 4'h0 && write_addr_reg != ID_ADDR) begin
                        if (write_addr_reg == REG0_ADDR) begin
                            if (write_strb_reg[0]) reg0[7:0] <= write_data_reg[7:0];
                            if (write_strb_reg[1]) reg0[15:8] <= write_data_reg[15:8];
                            if (write_strb_reg[2]) reg0[23:16] <= write_data_reg[23:16];
                            if (write_strb_reg[3]) reg0[31:24] <= write_data_reg[31:24];
                        end else if (write_addr_reg == REG1_ADDR) begin
                            if (write_strb_reg[0]) reg1[7:0] <= write_data_reg[7:0];
                            if (write_strb_reg[1]) reg1[15:8] <= write_data_reg[15:8];
                            if (write_strb_reg[2]) reg1[23:16] <= write_data_reg[23:16];
                            if (write_strb_reg[3]) reg1[31:24] <= write_data_reg[31:24];
                        end else if (write_addr_reg == REG2_ADDR) begin
                            if (write_strb_reg[0]) reg2[7:0] <= write_data_reg[7:0];
                            if (write_strb_reg[1]) reg2[15:8] <= write_data_reg[15:8];
                            if (write_strb_reg[2]) reg2[23:16] <= write_data_reg[23:16];
                            if (write_strb_reg[3]) reg2[31:24] <= write_data_reg[31:24];
                        end
                    end
                end
                
                // Set bvalid when ready to respond
                if (write_resp_delay_counter >= 3'd3) begin
                    bvalid_reg <= 1'b1;
                    bresp_reg <= write_resp_reg;
                end
            end
            
            // Handle write response completion
            if (bvalid_reg && bready) begin
                bvalid_reg <= 1'b0;
                write_transaction_pending <= 1'b0;
            end
            
            // Handle read address channel
            if (arvalid && arready) begin
                read_addr_reg <= araddr;
                read_transaction_pending <= 1'b1;
                read_resp_delay_counter <= 3'd0;
                
                // Determine response and data based on address
                if (araddr[7:4] != 4'h0) begin
                    read_resp_reg <= RESP_DECERR;
                    rdata_reg <= 32'h00000000;
                end else if (araddr == ID_ADDR) begin
                    read_resp_reg <= RESP_OKAY;
                    rdata_reg <= 32'h5A5A0003;
                end else if (araddr == REG0_ADDR) begin
                    read_resp_reg <= RESP_OKAY;
                    rdata_reg <= reg0;
                end else if (araddr == REG1_ADDR) begin
                    read_resp_reg <= RESP_OKAY;
                    rdata_reg <= reg1;
                end else if (araddr == REG2_ADDR) begin
                    read_resp_reg <= RESP_OKAY;
                    rdata_reg <= reg2;
                end else begin
                    read_resp_reg <= RESP_DECERR;
                    rdata_reg <= 32'h00000000;
                end
            end
            
            // Process read transaction after delay
            if (read_transaction_pending) begin
                read_resp_delay_counter <= read_resp_delay_counter + 1'b1;
                
                // Set rvalid when ready to respond
                if (read_resp_delay_counter >= 3'd3) begin
                    rvalid_reg <= 1'b1;
                end
            end
            
            // Handle read response completion
            if (rvalid_reg && rready) begin
                rvalid_reg <= 1'b0;
                read_transaction_pending <= 1'b0;
            end
        end
    end

endmodule
