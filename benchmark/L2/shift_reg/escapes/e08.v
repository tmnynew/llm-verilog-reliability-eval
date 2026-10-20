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

    always @(posedge clk) begin
        if (!rst_n) begin
            shift_reg <= 8'b0;
        end else begin
            case (mode)
                2'b00: // hold
                    shift_reg <= shift_reg;
                2'b01: // left shift
                    shift_reg <= {shift_reg[6:0], s_in};
                2'b10: // right shift
                    shift_reg <= {s_in, shift_reg[7:1]};
                2'b11: // parallel load
                    shift_reg <= d_in;
                default:
                    shift_reg <= shift_reg;
            endcase
        end
    end

endmodule
