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
    reg [AW:0] cnt;

    wire wr_accept = wr_en && !full;
    wire rd_accept = rd_en && !empty;

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            cnt <= 0;
            full <= 1'b0;
            empty <= 1'b1;
            rd_data <= {DW{1'b0}};
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
                cnt <= cnt + 1'b1;
            end else if (!wr_accept && rd_accept) begin
                cnt <= cnt - 1'b1;
            end

            full <= (cnt == DEPTH);
            empty <= (cnt == 0);
        end
    end

    always @(*) begin
        count = cnt;
    end

endmodule
