# 题库实现进度（Roadmap）

论文表 2 列出 30 题（L1/L2/L3 各 10 题），本仓库已全部实现并标记为 `ready`；每题包含两版功能规范、黄金参考模型、自检测试台、变异体与等价变异体清单，实现标准见 `docs/problem_format.md`。

| 层级 | 题目（10 题） |
|---|---|
| L1 组合逻辑 | priority_encoder8, seg7_decoder, parity_gen8, comparator4, barrel_shifter8, cla_adder4, mux8_1, gray_conv4, bcd_adder, lzc8 |
| L2 时序逻辑 | counter_param, seq_detector_1011, debounce, clk_divider, pwm_gen, shift_reg, ring_counter, edge_detect, watchdog, pulse_stretch |
| L3 系统级 | sync_fifo, uart, spi_master, i2c_master, rv32_datapath, spi_slave, ps2_rx, vga_timing, simple_dma, axi_lite_slave |

## 测试台变异得分（Icarus 仿真，`vleval mutate --n 20` + `vleval mutation-score`）

| 题目 | 变异体 | 杀死 | 等价（人工确认） | 得分 |
|---|---|---|---|---|
| priority_encoder8 | 12 | 11 | 1 | 100 % |
| seg7_decoder | 20 | 18 | 2 | 100 % |
| parity_gen8 | 2 | 2 | 0 | 100 % |
| comparator4 | 9 | 9 | 0 | 100 % |
| barrel_shifter8 | 7 | 6 | 1 | 100 % |
| cla_adder4 | 20 | 20 | 0 | 100 % |
| mux8_1 | 1 | 1 | 0 | 100 % |
| gray_conv4 | 7 | 7 | 0 | 100 % |
| bcd_adder | 14 | 13 | 1 | 100 % |
| lzc8 | 13 | 13 | 0 | 100 % |
| counter_param | 11 | 11 | 0 | 100 % |
| seq_detector_1011 | 17 | 15 | 2 | 100 % |
| debounce | 19 | 19 | 0 | 100 % |
| clk_divider | 16 | 16 | 0 | 100 % |
| pwm_gen | 17 | 16 | 1 | 100 % |
| shift_reg | 14 | 14 | 0 | 100 % |
| ring_counter | 14 | 14 | 0 | 100 % |
| edge_detect | 20 | 20 | 0 | 100 % |
| watchdog | 16 | 16 | 0 | 100 % |
| pulse_stretch | 13 | 13 | 0 | 100 % |
| sync_fifo | 20 | 19 | 1 | 100 % |
| uart | 20 | 16 | 4 | 100 % |
| spi_master | 20 | 17 | 3 | 100 % |
| spi_slave | 20 | 17 | 3 | 100 % |
| ps2_rx | 20 | 16 | 4 | 100 % |
| vga_timing | 20 | 20 | 0 | 100 % |
| simple_dma | 20 | 19 | 1 | 100 % |
| axi_lite_slave | 20 | 18 | 2 | 100 % |
| rv32_datapath | 20 | 20 | 0 | 100 % |
| i2c_master | 20 | 14 | 6 | 100 % |
| **合计** | **462** | **430** | **32** | **100 %** |

说明：
- 变异体数量少于 20 的题目（如 `parity_gen8`、`mux8_1` 只有一行 `assign`）是因为代码中可变异位置不足；论文中"每题 20 个"以生成器候选数为上限。
- 变异生成器不对 `parameter` 默认值和 `for` 循环头部取变异：前者对测试台不可观察（测试台显式传参或按默认参数实例化时两者都能覆盖到默认值以外的分支），后者产生不可终止的变异体（例如 `k = k + 1 → k = k - 1`），会拖死仿真器与综合器。
- 被剔除的等价变异体全部属于"不可达的 default 分支/case 项、复位后必被重新装载的内部寄存器的复位值、过宽计数器、被握手门控从而不可能同时成立的条件、规范未约束的空闲相位长度"等在仿真中不可观察的变化，理由逐条记录在各题 `equivalent.txt`（含复核人）。其中删除不可达 `default` 的变异体在综合阶段会被判为 E6，`vleval mutation-score --kill-on-synth` 可将其计入杀死。
- L3 测试台按事务级组织（协议监视器 + 参考模型/反应式对端模型），每题 100～3 000 个检查点，并按 `func/reset/timing/proto/state` 打标签；单次仿真时间均在 1 s 以内。

## 尚未完成的工作

1. `reference_resources`（LUT/FF/Fmax）目前为 Yosys 预筛估算值（`meta.json` 中 `reference_tool: yosys`，无 Fmax）；需在装有 Vivado 的机器上运行 `vleval --vivado reference` 覆盖为权威值。
2. 综合后仿真（E9 中"RTL 仿真通过、综合后仿真失败"分支）尚未自动化，当前 E9 仅依据综合 Error + 静态线索。
3. Web 界面为最小实现，配额按 `X-Student-Id` 头计数，正式部署需接入校园统一认证。
