module watchdog #(parameter TIMEOUT = 64) (
    input clk,
    input rst_n,
    input enable,
    input kick,
    output timeout
);

    reg [6:0] counter; // ceil(log2(TIMEOUT+1)) = 7 bits to count up to TIMEOUT
    reg timeout_r;

    assign timeout = timeout_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 7'b0;
            timeout_r <= 1'b0;
        end else begin
            if (kick || !enable) begin
                counter <= 7'b0;
                timeout_r <= 1'b0;
            end else if (enable && !timeout_r) begin
                if (counter < TIMEOUT[6:0]) begin
                    counter <= counter + 1'b1;
                end else begin
                    timeout_r <= 1'b1;
                end
            end
        end
    end

endmodule
