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

    reg [31:0] reg0, reg1, reg2;
    reg [31:0] write_reg_data;
    reg [1:0] write_resp;
    reg write_done;
    reg [31:0] read_reg_data;
    reg [1:0] read_resp;
    reg read_done;
    reg [1:0] state_write;
    reg [1:0] state_read;
    
    parameter IDLE = 2'b00;
    parameter WRITE_PENDING = 2'b01;
    parameter WRITE_DONE = 2'b10;
    
    parameter READ_IDLE = 2'b00;
    parameter READ_PENDING = 2'b01;
    parameter READ_DONE = 2'b10;

    // Write registers initialization
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg0 <= 32'h0;
            reg1 <= 32'h0;
            reg2 <= 32'h0;
        end else if (write_done && write_resp == 2'b00 && 
                     (awaddr[7:2] == 6'h0 || awaddr[7:2] == 6'h1 || awaddr[7:2] == 6'h2)) begin
            if (awaddr[7:2] == 6'h0) begin
                if (wstrb[0]) reg0[7:0] <= wdata[7:0];
                if (wstrb[1]) reg0[15:8] <= wdata[15:8];
                if (wstrb[2]) reg0[23:16] <= wdata[23:16];
                if (wstrb[3]) reg0[31:24] <= wdata[31:24];
            end else if (awaddr[7:2] == 6'h1) begin
                if (wstrb[0]) reg1[7:0] <= wdata[7:0];
                if (wstrb[1]) reg1[15:8] <= wdata[15:8];
                if (wstrb[2]) reg1[23:16] <= wdata[23:16];
                if (wstrb[3]) reg1[31:24] <= wdata[31:24];
            end else if (awaddr[7:2] == 6'h2) begin
                if (wstrb[0]) reg2[7:0] <= wdata[7:0];
                if (wstrb[1]) reg2[15:8] <= wdata[15:8];
                if (wstrb[2]) reg2[23:16] <= wdata[23:16];
                if (wstrb[3]) reg2[31:24] <= wdata[31:24];
            end
        end
    end

    // Write channel handshake and response
    assign awready = (state_write == IDLE) ? 1'b1 : 1'b0;
    assign wready = (state_write == IDLE) ? 1'b1 : 1'b0;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_write <= IDLE;
            write_done <= 1'b0;
            write_resp <= 2'b00;
        end else begin
            case (state_write)
                IDLE: begin
                    if (awvalid && wvalid) begin
                        if ({awaddr[7:2], 2'b00} >= 8'h10 && {awaddr[7:2], 2'b00} <= 8'hFF) begin
                            write_resp <= 2'b11; // DECERR
                            write_done <= 1'b1;
                            state_write <= WRITE_DONE;
                        end else if (awaddr[7:2] == 6'h3) begin  // Only read register at offset 0x0C
                            write_resp <= 2'b10; // SLVERR
                            write_done <= 1'b1;
                            state_write <= WRITE_DONE;
                        end else if (awaddr[7:2] == 6'h0 || awaddr[7:2] == 6'h1 || awaddr[7:2] == 6'h2) begin
                            write_resp <= 2'b00; // OKAY
                            write_done <= 1'b1;
                            state_write <= WRITE_DONE;
                        end else begin
                            write_resp <= 2'b11; // DECERR for out of range
                            write_done <= 1'b1;
                            state_write <= WRITE_DONE;
                        end
                    end
                end
                WRITE_DONE: begin
                    if (bready) begin
                        write_done <= 1'b0;
                        state_write <= IDLE;
                    end
                end
                default: state_write <= IDLE;
            endcase
        end
    end
    
    assign bvalid = write_done;
    assign bresp = write_resp;

    // Read channel
    always @(*) begin
        if ({araddr[7:2], 2'b00} >= 8'h10 && {araddr[7:2], 2'b00} <= 8'hFF) begin
            read_reg_data = 32'h0;
            read_resp = 2'b11; // DECERR
        end else if (araddr[7:2] == 6'h0) begin
            read_reg_data = reg0;
            read_resp = 2'b00; // OKAY
        end else if (araddr[7:2] == 6'h1) begin
            read_reg_data = reg1;
            read_resp = 2'b00; // OKAY
        end else if (araddr[7:2] == 6'h2) begin
            read_reg_data = reg2;
            read_resp = 2'b00; // OKAY
        end else if (araddr[7:2] == 6'h3) begin
            read_reg_data = 32'h5A5A0003; // ID register
            read_resp = 2'b00; // OKAY
        end else begin
            read_reg_data = 32'h0;
            read_resp = 2'b11; // DECERR
        end
    end
    
    assign arready = (state_read == READ_IDLE) ? 1'b1 : 1'b0;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_read <= READ_IDLE;
            read_done <= 1'b0;
        end else begin
            case (state_read)
                READ_IDLE: begin
                    if (arvalid) begin
                        read_done <= 1'b1;
                        state_read <= READ_DONE;
                    end
                end
                READ_DONE: begin
                    if (rready) begin
                        read_done <= 1'b0;
                        state_read <= READ_IDLE;
                    end
                end
                default: state_read <= READ_IDLE;
            endcase
        end
    end
    
    assign rvalid = read_done;
    assign rdata = read_reg_data;
    assign rresp = read_resp;

endmodule
