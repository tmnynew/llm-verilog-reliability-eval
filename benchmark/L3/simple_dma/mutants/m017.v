// MUTANT m017 AOR line 60: '-' -> '+'
// Golden reference: byte-copy DMA, read-then-write per byte, 2 cycles per byte
module simple_dma (
    input            clk,
    input            rst_n,
    input            start,
    input      [7:0] src,
    input      [7:0] dst,
    input      [7:0] len,
    output           busy,
    output reg       done,
    output reg [7:0] mem_addr,
    output     [7:0] mem_wdata,
    output reg       mem_we,
    output reg       mem_re,
    input      [7:0] mem_rdata
);
    localparam IDLE = 2'd0, RD = 2'd1, WR = 2'd2;
    reg [1:0] state;
    reg [7:0] src_r, dst_r, len_r, idx;

    assign busy      = (state != IDLE);
    assign mem_wdata = mem_rdata;

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= IDLE;
            done     <= 1'b0;
            mem_we   <= 1'b0;
            mem_re   <= 1'b0;
            mem_addr <= 8'd0;
            idx      <= 8'd0;
            src_r    <= 8'd0;
            dst_r    <= 8'd0;
            len_r    <= 8'd0;
        end else begin
            done   <= 1'b0;
            mem_we <= 1'b0;
            mem_re <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    src_r <= src;
                    dst_r <= dst;
                    len_r <= len;
                    idx   <= 8'd0;
                    if (len == 8'd0) begin
                        done <= 1'b1;
                    end else begin
                        state    <= RD;
                        mem_re   <= 1'b1;
                        mem_addr <= src;
                    end
                end
                RD: begin
                    state    <= WR;
                    mem_we   <= 1'b1;
                    mem_addr <= dst_r + idx;
                end
                WR: begin
                    idx <= idx + 8'd1;
                    if (idx == len_r + 8'd1) begin
                        state <= IDLE;
                        done  <= 1'b1;
                    end else begin
                        state    <= RD;
                        mem_re   <= 1'b1;
                        mem_addr <= src_r + idx + 8'd1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
