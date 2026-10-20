module watchdog #(parameter TIMEOUT = 64) (
    input clk,
    input rst_n,
    input enable,
    input kick,
    output timeout
);

    reg [6:0] counter; // ceil(log2(TIMEOUT+1)) = 7 bits for values 0 to 64
    reg timeout_r;

    assign timeout = timeout_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 7'b0;
            timeout_r <= 1'b0;
        end else begin
            if (!enable || kick) begin
                counter <= 7'b0;
                timeout_r <= 1'b0;
            end else if (counter < TIMEOUT) begin
                counter <= counter + 1'b1;
            end else if (counter == TIMEOUT) begin
                timeout_r <= 1'b1;
            end
        end
    end

endmodule
