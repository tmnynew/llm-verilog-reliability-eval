// MUTANT m012 SDL line 41: "wr_ptr      <= wr_ptr + 1'b1;" -> '/* statement removed */'
// Golden reference: single-clock synchronous FIFO with registered read data
module sync_fifo #(
    parameter DW    = 8,
    parameter DEPTH = 16
) (
    input             clk,
    input             rst_n,
    input             wr_en,
    input  [DW-1:0]   wr_data,
    input             rd_en,
    output reg [DW-1:0] rd_data,
    output            full,
    output            empty,
    output reg [4:0]  count
);
    localparam AW = (DEPTH <= 2)   ? 1 :
                    (DEPTH <= 4)   ? 2 :
                    (DEPTH <= 8)   ? 3 :
                    (DEPTH <= 16)  ? 4 :
                    (DEPTH <= 32)  ? 5 :
                    (DEPTH <= 64)  ? 6 :
                    (DEPTH <= 128) ? 7 : 8;

    reg [DW-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wr_ptr, rd_ptr;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);

    wire do_wr = wr_en && !full;
    wire do_rd = rd_en && !empty;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            count  <= 5'd0;
        end else begin
            if (do_wr) begin
                mem[wr_ptr] <= wr_data;
                /* statement removed */
            end
            if (do_rd) begin
                rd_data <= mem[rd_ptr];
                rd_ptr  <= rd_ptr + 1'b1;
            end
            case ({do_wr, do_rd})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule
