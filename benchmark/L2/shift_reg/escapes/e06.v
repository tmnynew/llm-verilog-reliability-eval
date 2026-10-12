module shift_reg (
    input clk,
    input rst_n,
    input [1:0] mode,
    input [7:0] d_in,
    input s_in,
    output [7:0] q,
    output s_out
);

    reg [7:0] shift_reg_q;
    
    assign q = shift_reg_q;
    assign s_out = (mode == 2'b01) ? shift_reg_q[7] : 
                   (mode == 2'b10) ? shift_reg_q[0] : 1'bx;

    always @(posedge clk) begin
        if (!rst_n) begin
            shift_reg_q <= 8'b0;
        end else begin
            case (mode)
                2'b00: shift_reg_q <= shift_reg_q;          // hold
                2'b01: shift_reg_q <= {shift_reg_q[6:0], s_in};  // left shift
                2'b10: shift_reg_q <= {s_in, shift_reg_q[7:1]};  // right shift
                2'b11: shift_reg_q <= d_in;               // parallel load
                default: shift_reg_q <= shift_reg_q;
            endcase
        end
    end

endmodule
