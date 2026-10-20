module sync_fifo #(parameter DW = 8, parameter DEPTH = 16) (
    input clk,
    input rst_n,
    input wr_en,
    input [DW-1:0] wr_data,
    input rd_en,
    output reg [DW-1:0] rd_data,
    output reg full,
    output reg empty,
    output reg [4:0] count
);

    localparam AW = $clog2(DEPTH);
    
    reg [DW-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wr_ptr;
    reg [AW-1:0] rd_ptr;
    reg [4:0] count_reg;
    
    wire wr_accept;
    wire rd_accept;
    
    assign wr_accept = wr_en && !full;
    assign rd_accept = rd_en && !empty;
    
    integer i;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count_reg <= 0;
            full <= 1'b0;
            empty <= 1'b1;
            rd_data <= 0;
        end else begin
            if (wr_accept) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            
            if (rd_accept) begin
                rd_data <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1'b1;
            end
            
            if (wr_accept && !rd_accept) begin
                count_reg <= count_reg + 1'b1;
            end else if (!wr_accept && rd_accept) begin
                count_reg <= count_reg - 1'b1;
            end
            
            full <= (count_reg == DEPTH);
            empty <= (count_reg == 0);
        end
    end
    
    always @(*) begin
        count = count_reg;
    end

endmodule
