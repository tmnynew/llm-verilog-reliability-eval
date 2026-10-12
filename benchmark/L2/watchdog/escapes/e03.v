module watchdog #(parameter TIMEOUT = 64) (
    input clk,
    input rst_n,
    input enable,
    input kick,
    output timeout
);
    // 计算计数器位宽
    localparam CNT_WIDTH = $clog2(TIMEOUT);
    
    reg [CNT_WIDTH-1:0] counter;
    reg timeout_r;
    
    wire clear_counter;
    wire increment_counter;
    
    // 清零条件：复位、enable=0或kick=1
    assign clear_counter = (~rst_n) || (~enable) || kick;
    
    // 递增条件：enable=1, kick=0, 且计数未达上限
    assign increment_counter = enable && (~kick) && (counter < TIMEOUT - 1);
    
    always @(posedge clk) begin
        if (~rst_n) begin
            counter <= 0;
            timeout_r <= 0;
        end
        else if (clear_counter) begin
            counter <= 0;
            timeout_r <= 0;
        end
        else if (increment_counter) begin
            counter <= counter + 1;
            if (counter + 1 >= TIMEOUT - 1) begin
                timeout_r <= 1;
            end
        end
        else if (enable && (~kick) && (counter == TIMEOUT - 1)) begin
            // 计数已达上限，保持timeout=1
            timeout_r <= 1;
        end
    end
    
    assign timeout = timeout_r;
endmodule
