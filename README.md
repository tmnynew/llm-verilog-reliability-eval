# 大模型辅助 Verilog 代码生成可靠性评估平台

论文《大模型生成 Verilog 代码可靠性评估实验设计》配套开源：分级题库、自检测试台、变异体、自动化评估平台与统计报表。

- **题库** `benchmark/`：L1 组合逻辑 / L2 时序逻辑 / L3 系统级各 10 题，共 30 题全部实现；每题含两版功能规范、黄金参考模型、测试台、变异体、等价变异体清单，测试台变异得分均为 100 %；L2/L3 题另含实验二用的弱测试台 `tb_weak.v`（变异得分 56～85 %）与逃逸样本 `escapes/`。
- **平台** `vleval/`：接口检查 → Verilog-2001 编译/Lint → 功能仿真（60 s 超时）→ 综合（Yosys 预筛 / Vivado 权威）→ 十类错误分类 → 修复循环（≤ 3 轮）→ SQLite → 论文表格与图。
- **可复现**：LLM 响应缓存、固定随机种子、确定性变异体生成、离线 golden oracle 自测。
- **数据** `data/`：论文第 4 节全部评测结果（DeepSeek-V4-Pro、Qwen3-Coder-Plus、GLM-5、Qwen3-Coder-30B-A3B，2026-10-02～04，3 300 样本）的 JSONL/CSV 快照，以及编译判据与弱测试台两项复判的结果（`data/rejudge/`）；论文表 4～表 6、图 4、图 5 可直接复算。

## 安装

```bash
git clone https://github.com/tmnynew/llm-verilog-reliability-eval.git && cd llm-verilog-reliability-eval
pip install -e ".[all]"          # 或最小安装 pip install -e .
```

EDA 工具（仿真器与 Lint 器在 `configs/tools.yaml` 中配置，Yosys 可选，Vivado 可选）：

| 工具 | 用途 | 安装 |
|---|---|---|
| Icarus Verilog ≥ 11 | 功能仿真（默认；论文数据用 14） | `apt install iverilog` |
| Verilator ≥ 5.0 | Lint / Verilog-2001 编译检查（默认），也可改作仿真器（`simulator: verilator`） | `apt install verilator` |
| Yosys ≥ 0.33 | 可综合性/锁存器秒级预筛 | `apt install yosys` |
| Vivado 2022+ | 权威综合、资源与 Fmax | Xilinx 官方 |

Windows 用户可直接解压 [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)（含 iverilog/yosys/verilator），并设置 `VERILATOR_ROOT`。

## 快速开始

```bash
# 1. 校验题库：静态检查 + golden 通过全部测试台
vleval validate --sim

# 2. 生成变异体并计算测试台变异得分（阈值 95 %）
vleval mutate --n 20
vleval mutation-score

# 2b. 实验二材料：弱测试台得分（L2/L3，56～85 %）与逃逸样本（从 data/ 挖出，每题 ≤ 10 份）
vleval mutation-score --tb weak --levels L2,L3
vleval escapes --levels L2,L3
vleval judge sync_fifo benchmark/L3/sync_fifo/escapes/e01.v --tb my_tb.v   # 学生用增强后的测试台重新判定

# 3. 离线自测整个流程（不调用任何 LLM）
vleval run --oracle --n 2 --repair 0 --db results/selftest.db
vleval report --db results/selftest.db --out results/selftest

# 4. 正式实验：复制 configs/models.example.yaml → configs/models.yaml，设置 API 密钥环境变量
export OPENAI_API_KEY=...
vleval run --model "Model B" --specs brief,detailed --strategies zero,few,constraint,cot --n 10 --repair 3
vleval report --db results/results.db --out results/report      # 论文表 4～6、图 4～5 的数据
vleval export --db results/results.db --out data                 # 发布用文本快照（JSONL/CSV，路径脱敏）

# 5. 判定单个文件（学生交互 / 调试）
vleval judge sync_fifo my_fifo.v

# 6. 教师复核首要错误（两名教师 → Cohen's Kappa）
vleval annotate 17 teacher-A E8
vleval annotate 17 teacher-B E8

# 6b. 分类规则更新后，把已有结果库迁移到现行规则（就地修改，先备份；不重新运行任何工具）
vleval reclassify --db results/results.db --dry-run

# 7. 学生 Web 界面
vleval web --port 8000

# 8. 在装有 Vivado 的机器上记录参考实现 LUT/FF/Fmax（写入各题 meta.json）
vleval --vivado reference
```

`--vivado`（或 `configs/tools.yaml` 中 `enable_vivado: true`）启用 Vivado out-of-context 综合与实现（xc7a35t，200 MHz 约束，Fmax = 1/(T − WNS)）。

## 复现论文数字

论文第 4 节的表 4～表 6、图 4、图 5 以及正文引用的数字都可由 `data/` 中的文本快照重新算出，不需要结果库，也不需要 EDA 工具：

```bash
pip install -e ".[stats]"
vleval report --data data --pool "Model A,Model B,Model C" --no-figures --out results/report   # → tables.md、summary.json
```

该命令的输出已存档于 `data/report/`，各表与论文的对应关系如下。

| `tables.md` 中的小节 | 论文 | 内容 |
|---|---|---|
| `T4_passk`、`T4_tests` | 表 4、4.2 节 | pass@1（按题聚类自助法 95% 置信区间，20 000 次重抽样，种子 20261114）、pass@5；层级之间的两独立样本精确置换检验、模型之间按题配对的符号翻转置换检验 |
| `T5_synth` | 表 5、4.3 节 | 严格判据（IEEE 1364-2005 编译检查 + Vivado）与 Vivado 判据下的可综合率和 pass@1；意外锁存器、Lint 告警密度 |
| `F4_errors`、`problems` | 图 4、4.4 节 | 十类首要错误按层级、按题目的分布 |
| `T6_prompt` | 表 6、4.5 节 | 规范完整度 × 提示策略（模型 B 的 8 种配置），按题配对检验 |
| `F5_repair`、`resources` | 图 5、4.6 节 | 累计通过率随修复轮次的变化、按首要错误类型的 3 轮修复成功率、资源与 Fmax 相对参考实现之比 |
| `weak_tb` | 4.1 节 | 被正式测试台判为功能错误的 L2、L3 样本中能通过弱测试台的比例 |

同一题的 10 次采样并不独立，所有区间与检验都以题目为分析单位（`vleval/stats.py`）；把样本直接合并作 Wilson 区间或 Fisher 检验会高估显著性。持有结果库时可用 `vleval report --db results/results.db --rejudge data/rejudge` 得到相同结果；用 pandas 直接处理 CSV 的示例见 `data/README.md` 第 5 节。

## 目录

```
benchmark/            题库（manifest.yaml 列出全部 30 题及实现状态）
configs/              工具与模型配置（models.yaml 不入库）
data/                 论文评测数据快照：4 模型 3 300 样本、7 715 条判定，复判结果与报表存档（见 data/README.md）
docs/                 架构、题目格式、实现进度
tests/                pytest（纯 Python 单元测试 + 需要 EDA 工具的集成测试）
vleval/               平台源代码
.github/workflows/    CI：单元测试、golden 校验、变异得分
Dockerfile            Ubuntu + Verilator/Icarus/Yosys 运行环境
```

## 错误分类（论文表 2）与工具依据

| 编码 | 类别 | 平台证据 |
|---|---|---|
| E1 | 接口错误 | `extract.check_interface` |
| E2 | 语言子集兼容性 | Verilator `--default-language 1364-2005` / Icarus `-g2005` 编译错误（Verilog-2001/2005 子集，SystemVerilog 结构即报错） |
| E3 | 赋值语义错误 | 仿真失败 + Lint `BLKSEQ`/`COMBDLY` |
| E4 | 复位错误 | 测试台 `tag=reset` |
| E5 | 位宽与截断 | 测试台 `tag=width`，或仿真失败 + Lint `WIDTH*` |
| E6 | 意外锁存器 | 综合报告出现规范未要求的锁存器（Vivado `Register as Latch` / Yosys `LDCE`）；仅有 Lint `LATCH`/`CASEINCOMPLETE` 时只记为次要标签 |
| E7 | 状态机与时序错误 | 测试台 `tag=state`/`timing` |
| E8 | 协议错误 | 测试台 `tag=proto`/`handshake`（事务级断言） |
| E9 | 仿真专用结构 | 综合 Error 且代码含 `#`/`fork`/`wait` 等静态线索（综合后仿真尚未自动化） |
| E10 | 一般功能逻辑错误 | 仿真失败，但只有功能比对不符（`tag=func`），没有以上任何一类的证据 |

平台按“接口检查—编译—仿真—综合”的先后取最先失败阶段的类别作为首要错误，仿真阶段内以协议、复位、状态/时序标签优先。首要错误为 E10 的样本同时标记 `needs_review`：分类器不按题型猜测原因，进一步归因留给人工（实验一的任务；教师复核用 `vleval annotate`）。

## 开发

```bash
pip install -e ".[dev]"
pytest -q                 # 无 EDA 工具时自动跳过集成测试
ruff check vleval tests
```

新增题目请按 `benchmark/L*/<id>/` 的现有布局提供 `spec_brief.md`、`spec_detailed.md`、`interface.json`、`meta.json`、`golden.v`、`tb.v` 与 `mutants/`；测试台须以 `TB_RESULT PASS|FAIL` 收尾、失败时打印 `TB_FAIL tag=<reset|proto|state|timing|...> case=<n> exp=<v> got=<v>`，并经 `vleval validate --sim` 与 `vleval mutation-score`（≥95 %）校验。

## 版本记录

- **v0.2.0**（2026-11）：错误分类由九类改为十类，新增 E10 一般功能逻辑错误，取消“状态机 / 系统级题的无标签比对失败计为 E7”和“首要错误留空待复核”两条规则，`data/` 已按新规则重新导出（`vleval reclassify`）；统计方法改为以题目为分析单位（聚类自助法置信区间、置换检验）；新增 `data/rejudge/`（编译判据与弱测试台复判）和 `vleval report --data`。
- **v0.1.0**（2026-10）：首次发布。

## 许可证

MIT。题库中的黄金模型与测试台同样以 MIT 发布，可直接用于课堂。
