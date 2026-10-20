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

    reg [9:0] h_count_reg;
    reg [9:0] v_count_reg;
    reg hsync_reg;
    reg vsync_reg;
    reg de_reg;
    reg [9:0] x_reg;
    reg [9:0] y_reg;

    wire h_sync_start = (h_count_reg >= H_ACTIVE + H_FP) && (h_count_reg < H_ACTIVE + H_FP + H_SYNC);
    wire v_sync_start = (v_count_reg >= V_ACTIVE + V_FP) && (v_count_reg < V_ACTIVE + V_FP + V_SYNC);
    wire h_active = (h_count_reg < H_ACTIVE);
    wire v_active = (v_count_reg < V_ACTIVE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count_reg <= 10'd0;
            v_count_reg <= 10'd0;
            hsync_reg <= 1'b0;
            vsync_reg <= 1'b0;
            de_reg <= 1'b0;
            x_reg <= 10'd0;
            y_reg <= 10'd0;
        end else begin
            hsync_reg <= ~h_sync_start;
            vsync_reg <= ~v_sync_start;
            
            if (h_count_reg == H_TOTAL - 1) begin
                if (v_count_reg == V_TOTAL - 1) begin
                    v_count_reg <= 10'd0;
                end else begin
                    v_count_reg <= v_count_reg + 1'b1;
                end
                h_count_reg <= 10'd0;
            end else begin
                h_count_reg <= h_count_reg + 1'b1;
            end
            
            if (h_active && v_active) begin
                de_reg <= 1'b1;
                x_reg <= h_count_reg;
                y_reg <= v_count_reg;
            end else begin
                de_reg <= 1'b0;
                x_reg <= 10'd0;
                y_reg <= 10'd0;
            end
        end
    end

    assign hsync = hsync_reg;
    assign vsync = vsync_reg;
    assign de = de_reg;
    assign x = x_reg;
    assign y = y_reg;

endmodule
