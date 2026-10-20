module watchdog #(parameter TIMEOUT = 64) (
    input clk,
    input rst_n,
    input enable,
    input kick,
    output timeout
);
    reg [6:0] count; // ceil(log2(64)) = 6, but use 7 bits to handle up to 128
    reg timeout_r;
    
    // Calculate required width for counter
    localparam CNT_WIDTH = $clog2(TIMEOUT);
    
    wire timeout_limit = (count == (TIMEOUT - 1));
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            timeout_r <= 0;
        end else begin
            if (!enable || kick) begin
                count <= 0;
                if (kick) begin
                    timeout_r <= 0;
                end
            end else if (enable && !kick) begin
                if (count < (TIMEOUT - 1)) begin
                    count <= count + 1;
                end else begin
                    count <= count; // Hold at max value
                end
            end
            
            if (timeout_limit && enable && !kick) begin
                timeout_r <= 1;
            end
        end
    end
    
    assign timeout = timeout_r;
endmodule
