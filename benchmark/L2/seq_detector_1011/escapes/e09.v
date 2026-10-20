module seq_detector_1011 (
    input clk,
    input rst_n,
    input din,
    output det
);
    reg [1:0] state;
    parameter S0 = 2'b00, S1 = 2'b01, S2 = 2'b10, S3 = 2'b11;
    
    assign det = (state == S3 && din == 1'b1);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S0;
        else case (state)
            S0: state <= din ? S1 : S0;
            S1: state <= din ? S1 : S2;
            S2: state <= din ? S3 : S0;
            S3: state <= din ? S1 : S2;
            default: state <= S0;
        endcase
    end
endmodule
