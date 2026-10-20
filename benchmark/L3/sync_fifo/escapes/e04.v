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
    localparam CW = AW + 1;

    reg [DW-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wr_ptr;
    reg [AW-1:0] rd_ptr;
    reg [CW-1:0] count_int;

    wire wr_accept;
    wire rd_accept;

    assign wr_accept = wr_en && !full;
    assign rd_accept = rd_en && !empty;

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count_int <= 0;
            full <= 0;
            empty <= 1;
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
                count_int <= count_int + 1'b1;
            end else if (!wr_accept && rd_accept) begin
                count_int <= count_int - 1'b1;
            end

            full <= (count_int == DEPTH - 1) && wr_accept && !rd_accept ? 1'b1 :
                    (count_int == 1) && rd_accept && !wr_accept ? 1'b0 :
                    full;
            empty <= (count_int == 1) && rd_accept && !wr_accept ? 1'b1 :
                     (count_int == 0) && wr_accept && !rd_accept ? 1'b0 :
                     empty;
        end
    end

    always @(*) begin
        count = count_int;
    end

endmodule
