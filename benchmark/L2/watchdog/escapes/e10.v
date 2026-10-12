module watchdog #(parameter TIMEOUT = 64) (
    input clk,
    input rst_n,
    input enable,
    input kick,
    output reg timeout
);

    // 计算计数器位宽
    localparam CNT_WIDTH = $clog2(TIMEOUT);
    
    // 内部计数器
    reg [CNT_WIDTH-1:0] counter;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= {CNT_WIDTH{1'b0}};
            timeout <= 1'b0;
        end
        else begin
            if (!enable || kick) begin
                counter <= {CNT_WIDTH{1'b0}};
                timeout <= 1'b0;
            end
            else begin
                if (counter == (TIMEOUT - 1)) begin
                    // 已经达到超时阈值，保持不变
                    timeout <= 1'b1;
                end
                else if (counter == (TIMEOUT - 2)) begin
                    // 下一周期将达到超时阈值
                    counter <= counter + 1'b1;
                    timeout <= 1'b1;
                end
                else begin
                    counter <= counter + 1'b1;
                    timeout <= 1'b0;
                end
            end
        end
    end

endmodule
