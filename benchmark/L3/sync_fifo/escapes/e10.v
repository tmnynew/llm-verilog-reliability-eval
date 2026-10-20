module sync_fifo #(parameter DW = 8, parameter DEPTH = 16) (
    input clk,
    input rst_n,
    input wr_en,
    input [7:0] wr_data,
    input rd_en,
    output [7:0] rd_data,
    output full,
    output empty,
    output [4:0] count
);

localparam PTR_WIDTH = $clog2(DEPTH);
reg [PTR_WIDTH-1:0] wr_ptr;
reg [PTR_WIDTH-1:0] rd_ptr;
reg [4:0] count_reg;
wire [4:0] next_count;
reg [DW-1:0] mem [0:DEPTH-1];
reg [DW-1:0] rd_data_reg;

assign count = count_reg;
assign full = (count_reg == DEPTH[4:0]);
assign empty = (count_reg == 0);

assign next_count = 
    (!rst_n || (wr_en && !full && !rd_en)) ? count_reg + 1'b1 :
    (!rst_n || (rd_en && !empty && !wr_en)) ? count_reg - 1'b1 :
    (!rst_n || (wr_en && !full && rd_en && !empty)) ? count_reg :
    count_reg;

always @(posedge clk) begin
    if (!rst_n) begin
        wr_ptr <= 0;
        rd_ptr <= 0;
        count_reg <= 0;
        rd_data_reg <= 0;
    end else begin
        // Update pointers and data based on current state
        if (wr_en && !full) begin
            mem[wr_ptr] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
        
        if (rd_en && !empty) begin
            rd_data_reg <= mem[rd_ptr];
            rd_ptr <= rd_ptr + 1'b1;
        end
        
        count_reg <= next_count;
    end
end

assign rd_data = rd_data_reg;

endmodule
