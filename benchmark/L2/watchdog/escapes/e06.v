module watchdog #(parameter TIMEOUT = 64) (
    input clk,
    input rst_n,
    input enable,
    input kick,
    output timeout
);
    // 计算计数器位宽
    localparam CNT_WIDTH = $clog2(TIMEOUT + 1);
    
    reg [CNT_WIDTH-1:0] counter;
    reg timeout_r;
    
    assign timeout = timeout_r;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            timeout_r <= 0;
        end else begin
            if (!enable || kick) begin
                counter <= 0;
                timeout_r <= 0;
            end else if (counter < TIMEOUT) begin
                counter <= counter + 1;
                timeout_r <= 0;
            end else begin
                timeout_r <= 1;
            end
        end
    end
endmodule
