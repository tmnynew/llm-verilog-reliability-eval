module vga_timing #(
    parameter H_ACTIVE = 640, 
    parameter H_FP = 16, 
    parameter H_SYNC = 96, 
    parameter H_BP = 48, 
    parameter V_ACTIVE = 480, 
    parameter V_FP = 10, 
    parameter V_SYNC = 2, 
    parameter V_BP = 33
) (
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
    
    reg [9:0] cnt_x;
    reg [9:0] cnt_y;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_x <= 10'd0;
            cnt_y <= 10'd0;
        end else begin
            if (cnt_x == H_TOTAL - 1) begin
                if (cnt_y == V_TOTAL - 1) begin
                    cnt_x <= 10'd0;
                    cnt_y <= 10'd0;
                end else begin
                    cnt_x <= 10'd0;
                    cnt_y <= cnt_y + 1'b1;
                end
            end else begin
                cnt_x <= cnt_x + 1'b1;
            end
        end
    end
    
    wire in_h_active = (cnt_x < H_ACTIVE);
    wire in_v_active = (cnt_y < V_ACTIVE);
    wire in_h_sync = (cnt_x >= H_ACTIVE + H_FP) && (cnt_x < H_ACTIVE + H_FP + H_SYNC);
    wire in_v_sync = (cnt_y >= V_ACTIVE + V_FP) && (cnt_y < V_ACTIVE + V_FP + V_SYNC);
    
    assign hsync = ~in_h_sync;
    assign vsync = ~in_v_sync;
    assign de = in_h_active && in_v_active;
    assign x = in_h_active ? cnt_x : 10'd0;
    assign y = in_v_active ? cnt_y : 10'd0;

endmodule
