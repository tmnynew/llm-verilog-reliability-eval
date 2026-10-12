module seq_detector_1011 (
    input clk,
    input rst_n,
    input din,
    output det
);
    // 状态编码：S0=00, S1=01, S2=10, S3=11
    reg [1:0] state, next_state;
    reg det_reg;

    parameter S0 = 2'b00;
    parameter S1 = 2'b01;
    parameter S2 = 2'b10;
    parameter S3 = 2'b11;

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S0;
            det_reg  <= 1'b0;
        end else begin
            state    <= next_state;
            det_reg  <= (state == S3);
        end
    end

    always @(*) begin
        case (state)
            S0: next_state = din ? S1 : S0;
            S1: next_state = din ? S1 : S2;
            S2: next_state = din ? S3 : S0;
            S3: next_state = din ? S1 : S2;
            default: next_state = S0;
        endcase
    end

    assign det = det_reg;
endmodule
