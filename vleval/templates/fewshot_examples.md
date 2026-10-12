【示例 1：规范】
2 选 1 多路选择器：当 `sel` 为 1 时输出 `b`，否则输出 `a`；数据位宽 4 位。

【示例 1：代码】
```verilog
module mux2_4 (
    input  [3:0] a,
    input  [3:0] b,
    input        sel,
    output [3:0] y
);
    assign y = sel ? b : a;
endmodule
```

【示例 2：规范】
T 触发器：同步低有效复位 `rst_n` 使 `q` 清零；`t` 为 1 时 `q` 在每个时钟上升沿翻转，否则保持。

【示例 2：代码】
```verilog
module tff (
    input  clk,
    input  rst_n,
    input  t,
    output reg q
);
    always @(posedge clk) begin
        if (!rst_n)
            q <= 1'b0;
        else if (t)
            q <= ~q;
    end
endmodule
```
