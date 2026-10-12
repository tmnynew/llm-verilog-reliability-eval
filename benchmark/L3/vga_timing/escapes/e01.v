module vga_timing #(parameter H_ACTIVE = 640, parameter H_FP = 16, parameter H_SYNC = 96, parameter H_BP = 48, parameter V_ACTIVE = 480, parameter V_FP = 10, parameter V_SYNC = 2, parameter V_BP = 33) (
    input clk,
    input rst_n,
    output hsync,
    output vsync,
    output de,
    output [9:0] x,
    output [9:0] y
);
    localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    reg [9:0] hcnt;
    reg [9:0] vcnt;

    wire h_sync_start = (hcnt == H_ACTIVE + H_FP - 1);
    wire h_sync_end   = (hcnt == H_ACTIVE + H_FP + H_SYNC - 1);
    wire h_last       = (hcnt == H_TOTAL - 1);
    wire v_sync_start = (vcnt == V_ACTIVE + V_FP - 1);
    wire v_sync_end   = (vcnt == V_ACTIVE + V_FP + V_SYNC - 1);
    wire v_last       = (vcnt == V_TOTAL - 1);

    reg hsync_r;
    reg vsync_r;
    reg de_r;
    reg [9:0] x_r;
    reg [9:0] y_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            hcnt <= 10'd0;
            vcnt <= 10'd0;
        end else begin
            if (h_last) begin
                hcnt <= 10'd0;
                if (v_last)
                    vcnt <= 10'd0;
                else
                    vcnt <= vcnt + 10'd1;
            end else begin
                hcnt <= hcnt + 10'd1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            hsync_r <= 1'b1;
            vsync_r <= 1'b1;
            de_r    <= 1'b0;
            x_r     <= 10'd0;
            y_r     <= 10'd0;
        end else begin
            if (h_sync_start)
                hsync_r <= 1'b0;
            else if (h_sync_end)
                hsync_r <= 1'b1;

            if (v_sync_start)
                vsync_r <= 1'b0;
            else if (v_sync_end)
                vsync_r <= 1'b1;

            if (hcnt < H_ACTIVE && vcnt < V_ACTIVE) begin
                de_r <= 1'b1;
                x_r  <= hcnt;
                y_r  <= vcnt;
            end else begin
                de_r <= 1'b0;
                x_r  <= 10'd0;
                y_r  <= 10'd0;
            end
        end
    end

    assign hsync = hsync_r;
    assign vsync = vsync_r;
    assign de    = de_r;
    assign x     = x_r;
    assign y     = y_r;
endmodule
