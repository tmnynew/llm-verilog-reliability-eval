module seq_detector_1011 (
    input clk,
    input rst_n,
    input din,
    output det
);
    // 状态编码（独热码）
    localparam S0 = 3'b001; // 初始/无匹配
    localparam S1 = 3'b010; // 已匹配 "1"
    localparam S2 = 3'b100; // 已匹配 "10"

    reg [2:0] state, next_state;
    reg det_reg;

    always @(posedge clk) begin
        if (!rst_n)
            state <= S0;
        else
            state <= next_state;
    end

    always @(posedge clk) begin
        if (!rst_n)
            det_reg <= 1'b0;
        else
            det_reg <= (state == S2 && din == 1'b1);
    end

    always @(*) begin
        case (state)
            S0: next_state = (din == 1'b1) ? S1 : S0;
            S1: next_state = (din == 1'b0) ? S2 : S1;
            S2: next_state = (din == 1'b1) ? S0 : S0;
            default: next_state = S0;
        endcase
    end

    assign det = det_reg;
endmodule
