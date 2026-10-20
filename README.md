# 大模型辅助 Verilog 代码生成可靠性评估平台

论文《大模型生成 Verilog 代码可靠性评估实验设计》配套开源：分级题库、自检测试台、变异体、自动化评估平台与统计报表。

- **题库** `benchmark/`：L1 组合逻辑 / L2 时序逻辑 / L3 系统级各 10 题，共 30 题全部实现；每题含两版功能规范、黄金参考模型、测试台、变异体、等价变异体清单，测试台变异得分均为 100 %；L2/L3 题另含实验二用的弱测试台 `tb_weak.v`（变异得分 56～85 %）与逃逸样本 `escapes/`。
- **平台** `vleval/`：接口检查 → Verilog-2001 编译/Lint → 功能仿真（60 s 超时）→ 综合（Yosys 预筛 / Vivado 权威）→ 九类错误分类 → 修复循环（≤ 3 轮）→ SQLite → 论文表格与图。
- **可复现**：LLM 响应缓存、固定随机种子、确定性变异体生成、离线 golden oracle 自测。
- **数据** `data/`：论文第 4 节全部评测结果（DeepSeek-V4-Pro、Qwen3-Coder-Plus、GLM-5、Qwen3-Coder-30B-A3B，2026-10-02～04，3 300 样本）的 JSONL/CSV 快照，表 5～8、图 3～6 可直接复算。

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
vleval report --db results/results.db --out results/report      # 表 5–8 + 图
vleval export --db results/results.db --out data                 # 发布用文本快照（JSONL/CSV，路径脱敏）

# 5. 判定单个文件（学生交互 / 调试）
vleval judge sync_fifo my_fifo.v

# 6. 教师复核首要错误（两名教师 → Cohen's Kappa）
vleval annotate 17 teacher-A E8
vleval annotate 17 teacher-B E8

# 7. 学生 Web 界面
vleval web --port 8000

# 8. 在装有 Vivado 的机器上记录参考实现 LUT/FF/Fmax（写入各题 meta.json）
vleval --vivado reference
```

`--vivado`（或 `configs/tools.yaml` 中 `enable_vivado: true`）启用 Vivado out-of-context 综合与实现（xc7a35t，200 MHz 约束，Fmax = 1/(T − WNS)）。

## 复现论文数字

论文第 4 节的表 5～表 8 以及正文引用的全部数字都可由 `data/` 中的快照或原始结果库重新算出：

```bash
# 原始结果库 results.db 见 GitHub Release v1.0-paper 附件 results.db.zip，解压到 results/（SHA-256 见 data/manifest.json）
vleval report --db results/results.db --out results/report               # → tables.md（表 5～8，口径与论文一致）
```

无需 `results.db` 时，`data/samples.csv` 与 `data/verdicts.csv` 可直接用 pandas 复算（示例见 `data/README.md` 第 5 节）；`data/report/paper_stats.txt` 与 `paper_data.json` 为论文 §4 全部数字及图 3～图 6 绘图数据的快照。

## 目录

```
benchmark/            题库（manifest.yaml 列出全部 30 题及实现状态）
configs/              工具与模型配置（models.yaml 不入库）
data/                 论文评测数据快照：4 模型 3 300 样本、7 715 条判定（见 data/README.md）
docs/                 架构、题目格式、实现进度
tests/                pytest（纯 Python 单元测试 + 需要 EDA 工具的集成测试）
vleval/               平台源代码
.github/workflows/    CI：单元测试、golden 校验、变异得分
Dockerfile            Ubuntu + Verilator/Icarus/Yosys 运行环境
```

## 错误分类（表 3）与工具依据

| 编码 | 类别 | 平台证据 |
|---|---|---|
| E1 | 接口错误 | `extract.check_interface` |
| E2 | 语言子集兼容性 | Verilator `--default-language 1364-2005` / Icarus `-g2005` 编译错误（Verilog-2001/2005 子集，SystemVerilog 结构即报错） |
| E3 | 赋值语义错误 | 仿真失败 + Lint `BLKSEQ`/`COMBDLY` |
| E4 | 复位错误 | 测试台 `tag=reset` |
| E5 | 位宽与截断 | 仿真失败 + Lint `WIDTH*` |
| E6 | 意外锁存器 | 综合报告锁存器（Vivado `Register as Latch` / Yosys `LDCE`）或 Lint `LATCH`/`CASEINCOMPLETE` |
| E7 | 状态机错误 | 测试台 `tag=state`/`timing`，或 `fsm` 题无标签比对失败 |
| E8 | 协议错误 | 测试台 `tag=proto`/`handshake`，或 L3 题无标签比对失败 |
| E9 | 仿真专用结构 | 综合 Error + `#`/`fork`/`wait` 等静态线索 |

证据不足的样本标记 `needs_review`，首要错误留空，由教师复核。

## 开发

```bash
pip install -e ".[dev]"
pytest -q                 # 无 EDA 工具时自动跳过集成测试
ruff check vleval tests
```

新增题目请按 `benchmark/L*/<id>/` 的现有布局提供 `spec_brief.md`、`spec_detailed.md`、`interface.json`、`meta.json`、`golden.v`、`tb.v` 与 `mutants/`；测试台须以 `TB_RESULT PASS|FAIL` 收尾、失败时打印 `TB_FAIL tag=<reset|proto|state|timing|...> case=<n> exp=<v> got=<v>`，并经 `vleval validate --sim` 与 `vleval mutation-score`（≥95 %）校验。

## 许可证

MIT。题库中的黄金模型与测试台同样以 MIT 发布，可直接用于课堂。
