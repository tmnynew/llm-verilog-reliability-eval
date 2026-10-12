module watchdog #(parameter TIMEOUT = 64) (
    input clk,
    input rst_n,
    input enable,
    input kick,
    output timeout
);
    reg [6:0] counter;
    reg timeout_r;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 7'b0;
            timeout_r <= 1'b0;
        end
        else begin
            if (!enable || kick) begin
                counter <= 7'b0;
                if (kick)
                    timeout_r <= 1'b0;
            end
            else if (counter < TIMEOUT - 1) begin
                counter <= counter + 1'b1;
            end
            else begin
                timeout_r <= 1'b1;
            end
        end
    end
    
    assign timeout = timeout_r;
endmodule
