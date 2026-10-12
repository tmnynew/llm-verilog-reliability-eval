module shift_reg (
    input clk,
    input rst_n,
    input [1:0] mode,
    input [7:0] d_in,
    input s_in,
    output [7:0] q,
    output s_out
);

    reg [7:0] shift_reg;
    
    assign q = shift_reg;
    assign s_out = shift_reg[7];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'b0;
        end else begin
            case (mode)
                2'b00: shift_reg <= shift_reg;          // 保持
                2'b01: shift_reg <= {shift_reg[6:0], s_in}; // 左移
                2'b10: shift_reg <= {s_in, shift_reg[7:1]}; // 右移
                2'b11: shift_reg <= d_in;              // 并行装载
                default: shift_reg <= shift_reg;
            endcase
        end
    end

endmodule
