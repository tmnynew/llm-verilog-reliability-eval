module vga_timing #(parameter H_ACTIVE = 640, parameter H_FP = 16, parameter H_SYNC = 96, parameter H_BP = 48, parameter V_ACTIVE = 480, parameter V_FP = 10, parameter V_SYNC = 2, parameter V_BP = 33) (
    input clk,
    input rst_n,
    output reg hsync,
    output reg vsync,
    output reg de,
    output reg [9:0] x,
    output reg [9:0] y
);

    wire [9:0] H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    wire [9:0] V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    reg [9:0] h_count;
    reg [9:0] v_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
            x <= 10'd0;
            y <= 10'd0;
            hsync <= 1'b0;
            vsync <= 1'b0;
            de <= 1'b0;
        end else begin
            // Update counters
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 1;
            end else begin
                h_count <= h_count + 1;
            end

            // Generate sync signals
            hsync <= !(h_count >= H_ACTIVE + H_FP && h_count < H_ACTIVE + H_FP + H_SYNC);
            vsync <= !(v_count >= V_ACTIVE + V_FP && v_count < V_ACTIVE + V_FP + V_SYNC);

            // Generate DE and coordinates
            if (h_count < H_ACTIVE && v_count < V_ACTIVE) begin
                de <= 1'b1;
                x <= h_count;
                y <= v_count;
            end else begin
                de <= 1'b0;
                x <= 10'd0;
                y <= 10'd0;
            end
        end
    end

endmodule
