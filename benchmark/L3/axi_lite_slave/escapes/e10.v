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

    // Register addresses (offsets)
    parameter REG0_ADDR = 8'h00;
    parameter REG1_ADDR = 8'h04;
    parameter REG2_ADDR = 8'h08;
    parameter ID_REG_ADDR = 8'h0C;
    
    // Response types
    parameter RESP_OKAY = 2'b00;
    parameter RESP_EXOKAY = 2'b01;
    parameter RESP_SLVERR = 2'b10;
    parameter RESP_DECERR = 2'b11;
    
    // Internal signals
    reg [31:0] reg0, reg1, reg2;
    reg [31:0] write_reg_data;
    reg [7:0] write_addr;
    reg [7:0] read_addr;
    reg write_state, read_state;
    reg write_pending, read_pending;
    reg [1:0] write_resp, read_resp;
    reg [31:0] read_data;
    
    // Write address and data registers
    reg [7:0] awaddr_reg;
    reg awaddr_valid;
    reg [31:0] wdata_reg;
    reg [3:0] wstrb_reg;
    reg wdata_valid;
    
    // AWREADY and WREADY control
    assign awready = ~awaddr_valid | (wdata_valid & ~write_pending);
    assign wready = ~wdata_valid | (awaddr_valid & ~write_pending);
    
    // ARREADY control
    assign arready = ~read_pending;
    
    // BVALID and RVALID control
    assign bvalid = write_pending & (write_state == 1);
    assign rvalid = read_pending & (read_state == 1);
    
    // BRESP and RRESP outputs
    assign bresp = write_resp;
    assign rresp = read_resp;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg0 <= 32'h0;
            reg1 <= 32'h0;
            reg2 <= 32'h0;
            
            awaddr_reg <= 8'h0;
            awaddr_valid <= 1'b0;
            wdata_reg <= 32'h0;
            wstrb_reg <= 4'h0;
            wdata_valid <= 1'b0;
            
            write_reg_data <= 32'h0;
            write_addr <= 8'h0;
            write_state <= 1'b0;
            write_pending <= 1'b0;
            write_resp <= RESP_OKAY;
            
            read_addr <= 8'h0;
            read_state <= 1'b0;
            read_pending <= 1'b0;
            read_resp <= RESP_OKAY;
            read_data <= 32'h0;
        end else begin
            // Handle AW channel
            if (awvalid && awready) begin
                awaddr_reg <= awaddr;
                awaddr_valid <= 1'b1;
            end
            
            // Handle W channel
            if (wvalid && wready) begin
                wdata_reg <= wdata;
                wstrb_reg <= wstrb;
                wdata_valid <= 1'b1;
            end
            
            // Process write transaction when both AW and W are valid
            if (awaddr_valid && wdata_valid && !write_pending) begin
                write_addr <= awaddr_reg;
                write_reg_data <= wdata_reg;
                
                // Check for decode error (address out of range or not aligned)
                if ((awaddr_reg >= 8'h10 && awaddr_reg < 8'h100) || 
                    (awaddr_reg[1:0] != 2'b00)) begin
                    write_resp <= RESP_DECERR;
                end
                // Check for write to read-only register
                else if (awaddr_reg == ID_REG_ADDR) begin
                    write_resp <= RESP_SLVERR;
                end
                // Valid write to writable registers
                else if (awaddr_reg == REG0_ADDR || awaddr_reg == REG1_ADDR || awaddr_reg == REG2_ADDR) begin
                    // Apply byte enables
                    if (awaddr_reg == REG0_ADDR) begin
                        if (wstrb_reg[0]) reg0[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) reg0[15:8] <= wdata_reg[15:8];
                        if (wstrb_reg[2]) reg0[23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) reg0[31:24] <= wdata_reg[31:24];
                    end
                    else if (awaddr_reg == REG1_ADDR) begin
                        if (wstrb_reg[0]) reg1[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) reg1[15:8] <= wdata_reg[15:8];
                        if (wstrb_reg[2]) reg1[23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) reg1[31:24] <= wdata_reg[31:24];
                    end
                    else if (awaddr_reg == REG2_ADDR) begin
                        if (wstrb_reg[0]) reg2[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) reg2[15:8] <= wdata_reg[15:8];
                        if (wstrb_reg[2]) reg2[23:16] <= wdata_reg[23:16];
                        if (wstrb_reg[3]) reg2[31:24] <= wdata_reg[31:24];
                    end
                    write_resp <= RESP_OKAY;
                end
                else begin
                    write_resp <= RESP_DECERR;
                end
                
                write_state <= 1'b0;
                write_pending <= 1'b1;
                
                // Clear the valid flags after processing
                awaddr_valid <= 1'b0;
                wdata_valid <= 1'b0;
            end
            
            // Handle write response state machine
            if (write_pending) begin
                if (write_state == 0) begin
                    write_state <= 1'b1;  // Move to response phase
                end else if (bready) begin
                    write_pending <= 1'b0;  // Clear pending when master accepts response
                end
            end
            
            // Handle AR channel
            if (arvalid && arready) begin
                read_addr <= araddr;
                read_pending <= 1'b1;
                read_state <= 1'b0;
                
                // Check for decode error
                if ((araddr >= 8'h10 && araddr < 8'h100) || 
                    (araddr[1:0] != 2'b00)) begin
                    read_resp <= RESP_DECERR;
                    read_data <= 32'h0;
                end
                // Read from registers
                else if (araddr == REG0_ADDR) begin
                    read_resp <= RESP_OKAY;
                    read_data <= reg0;
                end
                else if (araddr == REG1_ADDR) begin
                    read_resp <= RESP_OKAY;
                    read_data <= reg1;
                end
                else if (araddr == REG2_ADDR) begin
                    read_resp <= RESP_OKAY;
                    read_data <= reg2;
                end
                else if (araddr == ID_REG_ADDR) begin
                    read_resp <= RESP_OKAY;
                    read_data <= 32'h5A5A0003;  // ID register value
                end
                else begin
                    read_resp <= RESP_DECERR;
                    read_data <= 32'h0;
                end
            end
            
            // Handle read response state machine
            if (read_pending) begin
                if (read_state == 0) begin
                    read_state <= 1'b1;  // Move to response phase
                end else if (rready) begin
                    read_pending <= 1'b0;  // Clear pending when master accepts response
                end
            end
        end
    end
    
    // Output read data
    assign rdata = read_data;

endmodule
