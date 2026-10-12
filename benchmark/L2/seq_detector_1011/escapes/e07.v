module seq_detector_1011 (
    input clk,
    input rst_n,
    input din,
    output det
);
    // 状态编码：S0=0, S1=1, S10=2, S101=3, S1011=4
    reg [2:0] state, next_state;
    reg det_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            state  <= 3'd0;
            det_r  <= 1'b0;
        end else begin
            state  <= next_state;
            det_r  <= (next_state == 3'd4);
        end
    end

    always @(*) begin
        case (state)
            3'd0: next_state = din ? 3'd1 : 3'd0;
            3'd1: next_state = din ? 3'd1 : 3'd2;
            3'd2: next_state = din ? 3'd3 : 3'd0;
            3'd3: next_state = din ? 3'd4 : 3'd2;
            3'd4: next_state = din ? 3'd4 : 3'd2;
            default: next_state = 3'd0;
        endcase
    end

    assign det = det_r;
endmodule
