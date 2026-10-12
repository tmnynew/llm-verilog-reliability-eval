// MUTANT m009 URO line 31: '~' -> ''
// Golden reference: parameterised VGA horizontal/vertical timing generator
module vga_timing #(
    parameter H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_BP = 48,
    parameter V_ACTIVE = 480, V_FP = 10, V_SYNC = 2,  V_BP = 33
) (
    input        clk,
    input        rst_n,
    output       hsync,
    output       vsync,
    output       de,
    output [9:0] x,
    output [9:0] y
);
    localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    reg [9:0] hcnt, vcnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            hcnt <= 10'd0;
            vcnt <= 10'd0;
        end else if (hcnt == H_TOTAL - 1) begin
            hcnt <= 10'd0;
            vcnt <= (vcnt == V_TOTAL - 1) ? 10'd0 : vcnt + 10'd1;
        end else begin
            hcnt <= hcnt + 10'd1;
        end
    end

    assign hsync = (hcnt >= H_ACTIVE + H_FP && hcnt < H_ACTIVE + H_FP + H_SYNC);
    assign vsync = ~(vcnt >= V_ACTIVE + V_FP && vcnt < V_ACTIVE + V_FP + V_SYNC);
    assign de    = (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
    assign x     = de ? hcnt : 10'd0;
    assign y     = de ? vcnt : 10'd0;
endmodule
