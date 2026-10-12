// MUTANT m003 LOR line 19: '&' -> '|'
// Golden reference: PS/2 receiver with synchronisers, odd parity check and frame timeout
module ps2_rx #(
    parameter TIMEOUT = 200
) (
    input            clk,
    input            rst_n,
    input            ps2_clk,
    input            ps2_data,
    output reg [7:0] data,
    output reg       valid,
    output reg       err
);
    reg [2:0]  c_s;
    reg [1:0]  d_s;
    reg [3:0]  bit_cnt;
    reg [8:0]  sh;
    reg [15:0] tmr;

    wire fall = c_s[2] | ~c_s[1];
    wire din  = d_s[1];

    always @(posedge clk) begin
        if (!rst_n) begin
            c_s <= 3'b111;
            d_s <= 2'b11;
        end else begin
            c_s <= {c_s[1:0], ps2_clk};
            d_s <= {d_s[0], ps2_data};
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            bit_cnt <= 4'd0;
            valid   <= 1'b0;
            err     <= 1'b0;
            data    <= 8'd0;
            sh      <= 9'd0;
            tmr     <= 16'd0;
        end else begin
            valid <= 1'b0;
            err   <= 1'b0;
            if (fall) begin
                tmr <= 16'd0;
                if (bit_cnt == 4'd0) begin
                    if (din == 1'b0) bit_cnt <= 4'd1;
                end else if (bit_cnt == 4'd10) begin
                    bit_cnt <= 4'd0;
                    if (din == 1'b1 && (^sh) == 1'b1) begin
                        data  <= sh[7:0];
                        valid <= 1'b1;
                    end else begin
                        err <= 1'b1;
                    end
                end else begin
                    sh[bit_cnt - 1] <= din;
                    bit_cnt <= bit_cnt + 4'd1;
                end
            end else if (bit_cnt != 4'd0) begin
                if (tmr == TIMEOUT) begin
                    bit_cnt <= 4'd0;
                    tmr     <= 16'd0;
                end else begin
                    tmr <= tmr + 16'd1;
                end
            end
        end
    end
endmodule
