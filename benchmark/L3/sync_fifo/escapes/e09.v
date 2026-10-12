module sync_fifo #(parameter DW = 8, parameter DEPTH = 16) (
    input clk,
    input rst_n,
    input wr_en,
    input [DW-1:0] wr_data,
    input rd_en,
    output reg [DW-1:0] rd_data,
    output reg full,
    output reg empty,
    output reg [$clog2(DEPTH):0] count
);

localparam PTR_WIDTH = $clog2(DEPTH);
reg [DW-1:0] mem [0:DEPTH-1];
reg [PTR_WIDTH-1:0] wr_ptr;
reg [PTR_WIDTH-1:0] rd_ptr;

wire wr_accept = wr_en & ~full;
wire rd_accept = rd_en & ~empty;

always @(posedge clk) begin
    if (~rst_n) begin
        wr_ptr <= 0;
        rd_ptr <= 0;
        count <= 0;
        full <= 0;
        empty <= 1;
    end else begin
        if (wr_accept && rd_accept) begin
            // Both read and write accepted - same count
            wr_ptr <= wr_ptr + 1;
            rd_ptr <= rd_ptr + 1;
        end else if (wr_accept) begin
            // Only write accepted - increment count
            wr_ptr <= wr_ptr + 1;
            count <= count + 1;
        end else if (rd_accept) begin
            // Only read accepted - decrement count
            rd_ptr <= rd_ptr + 1;
            count <= count - 1;
        end
        
        // Update flags based on new count
        full <= (count == DEPTH - 1 && wr_accept && !rd_accept) || 
                (count == DEPTH && !rd_accept);
        empty <= (count == 1 && rd_accept && !wr_accept) ||
                 (count == 0 && !wr_accept);
        
        // If reset, force to initial state
        if (~rst_n) begin
            count <= 0;
            full <= 0;
            empty <= 1;
        end
    end
end

// Handle the case where we need to update flags after operations
always @(*) begin
    if (~rst_n) begin
        full = 0;
        empty = 1;
    end else begin
        full = (count == DEPTH);
        empty = (count == 0);
    end
end

// Write data to memory
always @(posedge clk) begin
    if (wr_accept) begin
        mem[wr_ptr] <= wr_data;
    end
end

// Read data from memory
always @(posedge clk) begin
    if (rd_accept) begin
        rd_data <= mem[rd_ptr];
    end
end

endmodule
