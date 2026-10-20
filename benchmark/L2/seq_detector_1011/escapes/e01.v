module seq_detector_1011 (
    input clk,
    input rst_n,
    input din,
    output det
);
    localparam S0 = 3'd0;
    localparam S1 = 3'd1;
    localparam S2 = 3'd2;
    localparam S3 = 3'd3;
    localparam S4 = 3'd4;

    reg [2:0] state, next_state;
    reg det_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S0;
            det_r <= 1'b0;
        end else begin
            state <= next_state;
            det_r <= (next_state == S4);
        end
    end

    always @(*) begin
        case (state)
            S0: next_state = din ? S1 : S0;
            S1: next_state = din ? S1 : S2;
            S2: next_state = din ? S3 : S0;
            S3: next_state = din ? S4 : S2;
            S4: next_state = din ? S4 : S2;
            default: next_state = S0;
        endcase
    end

    assign det = det_r;
endmodule
