module clk_divider (
    input clk,
    input rst_n,
    input [7:0] div,
    output tick,
    output clk_out
);
    reg [7:0] cnt;
    reg tick_r;
    reg clk_out_r;

    wire [7:0] half = div >> 1;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt <= 8'd0;
        end else begin
            if (cnt >= div - 1'b1)
                cnt <= 8'd0;
            else
                cnt <= cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            tick_r <= 1'b0;
        end else begin
            if (cnt >= div - 1'b1)
                tick_r <= 1'b1;
            else
                tick_r <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            clk_out_r <= 1'b1;
        end else begin
            if (cnt >= div - 1'b1)
                clk_out_r <= 1'b1;
            else if (cnt >= half)
                clk_out_r <= 1'b0;
        end
    end

    assign tick = tick_r;
    assign clk_out = clk_out_r;
endmodule
