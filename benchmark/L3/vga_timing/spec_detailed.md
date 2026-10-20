## 功能
VGA 行场时序发生器。像素时钟 clk 每个周期推进一个像素；一行包含有效区、前肩、同步、后肩四段，一帧包含相应的四段行。

## 参数
| 参数 | 默认值 | 说明 |
|---|---|---|
| H_ACTIVE / H_FP / H_SYNC / H_BP | 640 / 16 / 96 / 48 | 行有效像素、前肩、同步、后肩（单位：像素） |
| V_ACTIVE / V_FP / V_SYNC / V_BP | 480 / 10 / 2 / 33 | 场有效行、前肩、同步、后肩（单位：行） |

H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP（默认 800），V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP（默认 525）。所有参数取值保证行/场计数不超过 10 位。

## 端口
| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| clk | input | 1 | 像素时钟 |
| rst_n | input | 1 | **同步**复位，低电平有效 |
| hsync | output | 1 | 行同步，**低有效** |
| vsync | output | 1 | 场同步，**低有效** |
| de | output | 1 | 有效显示区标志 |
| x | output | 10 | 当前像素列坐标，de = 0 时为 0 |
| y | output | 10 | 当前像素行坐标，de = 0 时为 0 |

## 行为（均以 clk 上升沿为准）
1. 内部行计数 hcnt 在 0…H_TOTAL−1 循环，每个周期加 1；hcnt 回绕时场计数 vcnt 加 1，vcnt 在 0…V_TOTAL−1 循环。复位使 hcnt = vcnt = 0，复位期间 hsync = vsync = 1（de、x、y 在复位期间不作要求）。
2. `hsync = 0` 当且仅当 H_ACTIVE + H_FP ≤ hcnt < H_ACTIVE + H_FP + H_SYNC；其余时间为 1。
3. `vsync = 0` 当且仅当 V_ACTIVE + V_FP ≤ vcnt < V_ACTIVE + V_FP + V_SYNC；其余时间为 1。
4. `de = 1` 当且仅当 hcnt < H_ACTIVE 且 vcnt < V_ACTIVE；此时 x = hcnt，y = vcnt；de = 0 时 x = y = 0。
5. 允许的延迟窗口：五个输出可以整体比上述计数值定义的时刻**再晚 1 个周期**（例如全部经过一级寄存器），但必须一致；每帧内 de 为 1 的周期数为 H_ACTIVE·V_ACTIVE，hsync 低脉冲每行 1 个、宽 H_SYNC 个周期，vsync 低脉冲每帧 1 个、宽 V_SYNC·H_TOTAL 个周期。

## 时序示例（H_ACTIVE = 4，H_FP = 1，H_SYNC = 2，H_BP = 1，H_TOTAL = 8，处于有效行 vcnt = 0）
| 周期 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| hcnt | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 0 |
| de | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 1 |
| x | 0 | 1 | 2 | 3 | 0 | 0 | 0 | 0 | 0 |
| y | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| hsync | 1 | 1 | 1 | 1 | 1 | 0 | 0 | 1 | 1 |

周期 0 为复位释放后的第一个周期。
