module watchdog #(parameter TIMEOUT = 64) (
    input clk,
    input rst_n,
    input enable,
    input kick,
    output timeout
);

    // 计算计数位宽
    localparam CNT_WIDTH = (TIMEOUT <= 2) ? 1 :
                           (TIMEOUT <= 4) ? 2 :
                           (TIMEOUT <= 8) ? 3 :
                           (TIMEOUT <= 16) ? 4 :
                           (TIMEOUT <= 32) ? 5 :
                           (TIMEOUT <= 64) ? 6 :
                           (TIMEOUT <= 128) ? 7 :
                           (TIMEOUT <= 256) ? 8 :
                           (TIMEOUT <= 512) ? 9 :
                           (TIMEOUT <= 1024) ? 10 :
                           (TIMEOUT <= 2048) ? 11 :
                           (TIMEOUT <= 4096) ? 12 :
                           (TIMEOUT <= 8192) ? 13 :
                           (TIMEOUT <= 16384) ? 14 :
                           (TIMEOUT <= 32768) ? 15 : 16;

    reg [CNT_WIDTH-1:0] count;
    reg timeout_reg;

    wire kick_rise;
    reg kick_prev;

    // 检测 kick 上升沿
    always @(posedge clk) begin
        if (!rst_n)
            kick_prev <= 1'b0;
        else
            kick_prev <= kick;
    end

    assign kick_rise = kick & ~kick_prev;

    // 主逻辑
    always @(posedge clk) begin
        if (!rst_n) begin
            count <= {CNT_WIDTH{1'b0}};
            timeout_reg <= 1'b0;
        end
        else if (!enable) begin
            count <= {CNT_WIDTH{1'b0}};
            timeout_reg <= 1'b0;
        end
        else if (kick_rise) begin
            count <= {CNT_WIDTH{1'b0}};
            timeout_reg <= 1'b0;
        end
        else begin
            if (count < TIMEOUT - 1) begin
                count <= count + 1'b1;
                timeout_reg <= 1'b0;
            end
            else begin
                count <= count;
                timeout_reg <= 1'b1;
            end
        end
    end

    assign timeout = timeout_reg;

endmodule
