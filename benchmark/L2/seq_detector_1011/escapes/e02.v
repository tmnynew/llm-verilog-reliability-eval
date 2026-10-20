module seq_detector_1011 (
    input clk,
    input rst_n,
    input din,
    output det
);

reg [3:0] state;
reg det_reg;

// State encoding:
// 0000 - initial state
// 0001 - received '1'
// 0010 - received '10'
// 0011 - received '101'
// 0100 - received '1011' (match)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= 4'b0000;
        det_reg <= 1'b0;
    end else begin
        case (state)
            4'b0000: begin
                if (din == 1'b1)
                    state <= 4'b0001;
                else
                    state <= 4'b0000;
            end
            4'b0001: begin
                if (din == 1'b0)
                    state <= 4'b0010;
                else if (din == 1'b1)
                    state <= 4'b0001;
                else
                    state <= 4'b0000;
            end
            4'b0010: begin
                if (din == 1'b1)
                    state <= 4'b0011;
                else if (din == 1'b0)
                    state <= 4'b0010;
                else
                    state <= 4'b0000;
            end
            4'b0011: begin
                if (din == 1'b1)
                    state <= 4'b0100;
                else if (din == 1'b0)
                    state <= 4'b0010;
                else
                    state <= 4'b0000;
            end
            4'b0100: begin
                if (din == 1'b1)
                    state <= 4'b0001;
                else if (din == 1'b0)
                    state <= 4'b0010;
                else
                    state <= 4'b0000;
            end
        endcase

        // Output detection pulse
        if (state == 4'b0100)
            det_reg <= 1'b1;
        else
            det_reg <= 1'b0;
    end
end

assign det = det_reg;

endmodule
