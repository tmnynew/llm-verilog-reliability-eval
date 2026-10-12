// Golden reference: overlapping "1011" sequence detector, Mealy-style registered output (0 extra latency)
module seq_detector_1011 (
    input      clk,
    input      rst_n,
    input      din,
    output reg det
);
    localparam S0    = 2'd0,  // nothing matched
               S1    = 2'd1,  // "1"
               S10   = 2'd2,  // "10"
               S101  = 2'd3;  // "101"

    reg [1:0] state, next_state;
    reg       det_next;

    always @(*) begin
        next_state = S0;
        det_next   = 1'b0;
        case (state)
            S0:   next_state = din ? S1 : S0;
            S1:   next_state = din ? S1 : S10;
            S10:  next_state = din ? S101 : S0;
            S101: begin
                      next_state = din ? S1 : S10;   // "1011" + overlap: last "1" restarts as S1
                      det_next   = din;
                  end
            default: next_state = S0;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S0;
            det   <= 1'b0;
        end else begin
            state <= next_state;
            det   <= det_next;
        end
    end
endmodule
