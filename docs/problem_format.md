# 题目目录格式（Problem Format）

```
benchmark/<level>/<id>/
├── meta.json          # 元数据
├── interface.json     # 模块名、参数、端口（接口检查的依据）
├── spec_brief.md      # 简略版功能规范（一两句话）
├── spec_detailed.md   # 详细版功能规范（端口表、逐条行为、时序示例、允许的延迟窗口）
├── golden.v           # 黄金参考模型（Verilog-2001，上板验证）
├── tb.v               # 自检测试台（见 testbench_protocol.md）
├── tb_weak.v          # 实验二用弱测试台（仅 L2/L3，见下文）
├── equivalent.txt     # 人工确认的等价变异体（可选）
├── mutants/           # `vleval mutate` 生成，纳入版本控制以便复现
│   ├── index.json
│   └── m001.v …
└── escapes/           # 实验二用逃逸样本（仅 L2/L3）：`vleval escapes` 从 data/samples.jsonl 挖出
    ├── index.json     # 每份样本的来源（sample_id、模型、规范版本、提示策略、修复轮次、全测试台首要错误）
    └── e01.v …
```

## 弱测试台与逃逸样本（实验二）

`tb_weak.v` 与 `tb.v` 遵守同一协议、使用同一模块名 `tb_<id>`，但**只含标称路径的基本功能激励**：固定一组参数、
一两笔正常事务、对主要输出做轻量检查；不含复位值检查、边界/满空/回绕、非法输入、背压、中途复位、随机激励、
周期级参考模型与脉冲宽度检查。文件头注释逐条列出"未覆盖什么"，供教师核对。设计原则是**所有破坏基本功能的变异体
仍被杀死，只有时序/边界类变异体存活**，因此各题得分随"时序类变异体占比"而异：

| 题目 | 弱得分/% | 存活变异体 | 题目 | 弱得分/% | 存活变异体 |
|---|---|---|---|---|---|
| counter_param | 72.7 | tc 逻辑、MOD 回绕 | sync_fifo | 78.9 | 空/满/计数边界 |
| seq_detector_1011 | 73.3 | 重叠检测、复位值 | uart | 62.5 | 波特率/采样点、done 时序 |
| debounce | 63.2 | 复位值、计数器清零时机 | spi_master | 58.8 | sclk 周期/相位、done 宽度 |
| clk_divider | 68.8 | 复位值、占空比 | i2c_master | 78.6 | 读通路 ack/数据采样 |
| pwm_gen | 56.2 | 复位值、占空比锁存时机 | rv32_datapath | 60.0 | 移位/SLT、非法编码 |
| shift_reg | 57.1 | s_out、复位值 | spi_slave | 82.4 | miso 通路、复位值 |
| ring_counter | 78.6 | 右移、复位值 | ps2_rx | 81.2 | 奇偶/超时判定 |
| edge_detect | 70.0 | 下降沿模式、复位值 | vga_timing | 75.0 | 场时序、消隐期 x/y |
| watchdog | 75.0 | 精确超时周期、enable | simple_dma | 73.7 | 地址回绕、len=0、越界写 |
| pulse_stretch | 84.6 | 复位值、精确脉宽 | axi_lite_slave | 61.1 | 字节选通、DECERR/SLVERR、reg2 |

20 题得分 56.2～84.6 %，均值 70.6 %（`vleval mutation-score --tb weak`；超出 `WEAK_TARGET` 40～85 % 的题会被标记）。

`escapes/` 为**全测试台判为仿真失败、弱测试台却放过**的 LLM 生成代码，由 `vleval escapes --levels L2,L3` 从
`data/samples.jsonl` 中按固定种子、各模型交替抽取（初始代码与未通过样本的最终修复代码都纳入候选，去重），每题最多
10 份；候选不足时取全部（当前 pwm_gen 7、rv32_datapath 7、simple_dma 7、i2c_master 3、ps2_rx 3，其余 15 题各 10 份，共 177 份）。
学生用增强后的测试台重新判定这些样本（`vleval judge <id> escapes/eNN.v --tb my_tb.v`）并统计检出率。

## meta.json

| 字段 | 类型 | 说明 |
|---|---|---|
| id | str | 与目录名一致 |
| level | `L1`/`L2`/`L3` | 层级 |
| title | str | 中文题名 |
| tags | list | 用于错误分类的兜底证据：`fsm`（无标签功能失败 → E7）、`protocol`（→ E8），以及教学标签 `reset`/`width`/`default-branch` 等 |
| testbench_type | `exhaustive`/`cycle`/`transaction` | 比对策略 |
| allowed_latency | int | 规范中声明的允许输出延迟（周期） |
| clock_port | str/null | 时钟端口名，Vivado 用于施加时序约束；组合逻辑为 null |
| reference_resources | object | 参考实现的 `LUT`/`FF`/`Fmax_MHz`（`vleval reference --vivado` 填写） |
| status | `ready`/`planned` | 仅 `ready` 题目被加载 |

## interface.json

```json
{
  "module": "counter_param",
  "parameters": {"WIDTH": 8, "MOD": 200},
  "ports": [
    {"name": "clk", "direction": "input", "width": 1},
    {"name": "count", "direction": "output", "width": 8}
  ]
}
```

端口宽度按**默认参数**给出；生成代码若用 `[WIDTH-1:0]` 表达，接口检查会用默认参数折算，无法折算的宽度不判错（交给编译阶段）。

## 规范撰写规则

1. 两个版本只在详细程度上不同，**都不含编码风格约束**（`vleval validate` 会检查禁用词：非阻塞赋值、default 分支、禁用 initial 等）。
2. 详细版必须包含：端口表、复位方式（同步/异步、极性、复位值）、逐条行为、允许的延迟窗口、至少一个时序示例。
3. 复位统一为同步低有效 `rst_n`（课程约定），如需其他方式请在规范中显式说明。

## 新增题目流程

1. `benchmark/manifest.yaml` 中把状态改为 `ready`。
2. 编写上述文件；`golden.v` 需在 Basys3 上板验证并记录 `reference_resources`。
3. `vleval validate --sim` 确认 golden 通过测试台。
4. `vleval mutate --problem <id>`，`vleval mutation-score --problem <id>`；得分 < 95 % 时补强测试台，或把确认等价的变异体写入 `equivalent.txt`（附理由）。
5. 提 PR，CI 会重复第 3～4 步。
