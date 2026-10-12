module vga_timing #(parameter H_ACTIVE = 640, parameter H_FP = 16, parameter H_SYNC = 96, parameter H_BP = 48, parameter V_ACTIVE = 480, parameter V_FP = 10, parameter V_SYNC = 2, parameter V_BP = 33) (
    input clk,
    input rst_n,
    output hsync,
    output vsync,
    output de,
    output [9:0] x,
    output [9:0] y
);

    wire [9:0] H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    wire [9:0] V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    reg [9:0] x_reg;
    reg [9:0] y_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_reg <= 10'd0;
            y_reg <= 10'd0;
        end else begin
            if (x_reg == H_TOTAL - 1) begin
                if (y_reg == V_TOTAL - 1) begin
                    x_reg <= 10'd0;
                    y_reg <= 10'd0;
                end else begin
                    x_reg <= 10'd0;
                    y_reg <= y_reg + 1;
                end
            end else begin
                x_reg <= x_reg + 1;
            end
        end
    end

    assign x = x_reg;
    assign y = y_reg;

    wire h_sync_start = (x_reg >= H_ACTIVE + H_FP) && (x_reg < H_ACTIVE + H_FP + H_SYNC);
    wire v_sync_start = (y_reg >= V_ACTIVE + V_FP) && (y_reg < V_ACTIVE + V_FP + V_SYNC);

    assign hsync = ~h_sync_start;
    assign vsync = ~v_sync_start;

    assign de = (x_reg < H_ACTIVE) && (y_reg < V_ACTIVE);

endmodule
