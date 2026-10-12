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
    localparam AW = 4;
    reg [7:0] mem [0:15];
    reg [AW:0] wptr;
    reg [AW:0] rptr;
    reg [AW:0] cnt;
    reg [7:0] rdata;

    wire do_wr = wr_en && (rd_en ? !empty : !full);
    wire do_rd = rd_en && !empty;

    always @(posedge clk) begin
        if (!rst_n) begin
            wptr <= 0;
            rptr <= 0;
            cnt  <= 0;
        end else begin
            if (do_wr) begin
                mem[wptr[AW-1:0]] <= wr_data;
                wptr <= wptr + 1'b1;
            end
            if (do_rd) begin
                rptr <= rptr + 1'b1;
            end
            case ({do_wr, do_rd})
                2'b10: cnt <= cnt + 1'b1;
                2'b01: cnt <= cnt - 1'b1;
                default: cnt <= cnt;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rdata <= 8'hxx;
        end else if (do_rd) begin
            rdata <= mem[rptr[AW-1:0]];
        end
    end

    assign full  = (cnt == DEPTH);
    assign empty = (cnt == 0);
    assign count = cnt;
    assign rd_data = rdata;
endmodule
