# 论文评测数据（Paper data release）

本目录是论文《大模型生成 Verilog 代码可靠性评估实验设计》第 4 节全部评测结果的文本快照，由平台结果库 `results/results.db` 经 `vleval export` 导出，论文表 4～表 6、图 4、图 5 及正文数字均可由此复算（`vleval report --data data`，见第 5 节）。原始 SQLite 库（46 MB）不随仓库发布，其 SHA-256 记录在 `manifest.json` 中以便核对。

## 1. 数据来源

| 项目 | 内容 |
|---|---|
| 评测日期 | 2026-10-02 ～ 2026-10-04 |
| 被测模型 | Model A `deepseek-v4-pro`（DeepSeek 官方 API）；Model B `qwen3-coder-plus-2025-09-23`（阿里云百炼）；Model C `glm-5`（智谱）；Model D `qwen3-coder-30b-a3b-instruct`（开源权重，百炼托管推理） |
| 采样参数 | temperature = 0.2，max_tokens = 8 192，每题每配置 n = 10 |
| 配置矩阵 | Model B：2 版规范 × 4 种提示策略 = 8 配置 × 300 = 2 400 样本；Model A/C/D：仅主配置（detailed × zero）各 300 样本；合计 3 300 样本 |
| 修复 | 失败样本最多 3 轮错误反馈修复，共 7 715 条判定记录 |
| 判定工具 | Verilator 5.053（编译 + Lint，IEEE 1364-2005）、Icarus Verilog 14.0（功能仿真，60 s 超时）、Yosys 0.69（综合预筛）、Vivado 2024.1（权威综合与实现，xc7a35tcpg236-1，out-of-context，5 ns 约束） |
| 运行环境 | Windows 工作站；路径已脱敏（见第 4 节） |

## 2. 文件

| 文件 | 粒度 | 大小 | 用途 |
|---|---|---|---|
| `samples.jsonl` | 每行 1 个样本（3 300 行） | 28 MB | 完整记录：提示词、模型原始回复、代码、各轮判定（不含工具日志） |
| `samples.csv` | 每行 1 个样本（3 300 行） | 0.5 MB | 初始/最终结果摘要，适合直接计算 pass@k、可综合率、修复收敛率 |
| `verdicts.csv` | 每行 1 条判定（样本 × 轮次，7 715 行） | 0.9 MB | 逐轮判定扁平表 |
| `tool_logs.jsonl` | 每行 1 条判定 | 12 MB | Verilator / Icarus / Vivado 日志摘录与分类依据 `rationale` |
| `rejudge/vivado_recheck.csv` | 每行 1 个主配置编译失败样本（193 行） | 30 KB | 编译判据复判：把止于编译检查的初始代码送 Vivado 综合与实现（见第 6 节） |
| `rejudge/vivado_recheck_xsim.csv` | 每行 1 个 Vivado 综合通过的样本（57 行） | 4 KB | 上述样本用 Vivado 仿真器运行正式测试台的结果 |
| `rejudge/weak_tb_escape_rate.csv` | 每行 1 个被正式测试台判为仿真失败的 L2/L3 样本（1 021 行，全部配置） | 50 KB | 弱测试台复判 |
| `report/tables.md` | — | 12 KB | `vleval report --data data` 的输出：论文表 4～表 6、图 4、图 5 与正文引用的数字 |
| `report/summary.json` | — | 20 KB | 同上，机器可读（含图 4、图 5 的绘图数据） |
| `manifest.json` | — | — | 样本数、模型版本、源库校验和、脱敏规则、残留路径自检 |

## 3. 字段说明

### 3.1 样本级字段（`samples.jsonl` 顶层 / `samples.csv`）

| 字段 | 含义 |
|---|---|
| `sample_id` | 结果库主键，三个文件间以此关联 |
| `model`, `model_version` | 论文中的模型代号与实际调用的模型版本号 |
| `problem_id`, `level` | 题目 id（对应 `benchmark/L?/<problem_id>/`）与层级 L1/L2/L3 |
| `spec_version` | 功能规范版本：`brief` 简略 / `detailed` 详细 |
| `strategy` | 提示策略：`zero` 零样本 / `few` 少样本 / `constraint` 编码约束 / `cot` 思维链 |
| `idx` | 同一配置下第 0～9 次采样 |
| `temperature`, `created_at` | 采样温度、调用日期 |
| `prompt` | 发给模型的完整初始提示（系统 + 用户消息拼接） |
| `raw_response` | 模型对初始提示的原始回复（含说明文字与代码块） |
| `code` | **初始提取的代码**；若修复循环最终通过，则为**通过判定的最终版代码**。初始代码可用 `vleval.extract.extract_code(raw_response)` 重新提取 |
| `rounds` | 判定记录数组，`rounds[0]` 为修复前（论文"修复前"口径），之后每项为一轮修复后的判定 |

> 关于逐轮代码：平台现版本为每轮判定记录当轮代码与模型回复（`rounds[].code`、`rounds[].raw_response`），供实验四比较相邻修复轮次的差异。**本目录的 2026-10 评测数据产生于该字段加入之前，这两个字段均为 `null`**；中间轮次代码未保存，无法补录。

`samples.csv` 另含派生列：`n_rounds`（判定次数 = 1 + 修复轮数）、`initial_*`（`rounds[0]` 的 stage / passed / synthesizable / unintended_latch / primary_error / needs_review / lint_density）、`final_passed`、`final_stage`、`repaired`（修复后通过 = 1）、`final_LUT` / `final_FF` / `final_Fmax_MHz`（通过样本的 Vivado 实现结果）。

### 3.2 判定级字段（`rounds[]` / `verdicts.csv`）

| 字段 | 含义 |
|---|---|
| `round` | 0 = 修复前，1～3 = 第 k 轮修复后 |
| `stage` | 终止阶段：`interface` 接口检查失败 / `compile` 编译失败 / `simulation` 仿真失败 / `synthesis` 综合失败 / `passed` 全部通过 |
| `passed` | 仿真与综合均通过 |
| `sim_passed` | 功能仿真通过 |
| `synth_ok` | Vivado 综合与实现（opt/place/route）均无 Error，且未出现意外锁存器；**编译未通过的样本不会进入综合，此时为空（JSON 中为 `null`）** |
| `synthesizable` | 派生列：进入综合且综合、实现均无 Error，也未出现意外锁存器；论文表 5“可综合率（严格判据）”的分子 |
| `unintended_latch` | 综合推断出规范未要求的锁存器 |
| `tool_disagreement` | Yosys 预筛与 Vivado 判定不一致（以 Vivado 为准） |
| `needs_review` | 首要错误为 E10（仿真失败，但只有功能比对不符，没有其他类别的证据），进一步归因需人工完成 |
| `primary_error` | 首要错误类型 E1～E10（论文表 2），按论文 2.4 节的分类规则给出；通过的样本为空 |
| `errors` | 检出的全部错误类型（多标签；CSV 中以 `;` 分隔） |
| `lint_density` | 功能相关 Lint 告警密度（每 100 有效行），仅对编译通过的样本有值 |
| `lint_counts` | 各类 Verilator 告警计数（JSONL） |
| `failed_cases` | 测试台输出的失败事务 / 编译错误行（JSONL） |
| `resources` | `{"LUT", "FF", "Fmax_MHz"}`，仅通过样本有值；Fmax = 1/(5 ns − WNS) |
| `code`, `raw_response` | 当轮判定的代码与模型回复（JSONL）；本数据集中为 `null`，见上文说明 |

### 3.3 `tool_logs.jsonl`

`{"sample_id", "round", "compile", "sim", "synth", "rationale"}`：三个工具的日志摘录（截尾）与平台给出首要错误的依据文字。

## 4. 路径脱敏

导出时将本机路径替换为占位符，规则见 `manifest.json` 的 `redaction` 字段：`<repo>` 仓库根目录、`<tmp>` 每个样本的临时工作目录、`<home>` 用户目录、`<vivado>`、`<oss-cad-suite>` 工具安装目录。导出后自检 `residual_local_paths = 0`，即不含任何盘符路径。提示词、模型回复与代码原样保留，未做任何改动。

## 5. 复算论文数字

```bash
pip install -e ".[stats]"
vleval report --data data --pool "Model A,Model B,Model C" --no-figures --out results/report
```

只读取本目录的文本文件，不需要结果库和 EDA 工具；输出与 `report/tables.md`、`report/summary.json` 一致（置信区间用固定种子 20261114 的 20 000 次按题重抽样，检验均为精确置换检验，结果是确定的）。各小节与论文图表的对应关系见仓库根目录 `README.md`。同一题的 10 次采样并不独立，区间与检验都以题目为分析单位，不要把样本直接合并作 Wilson 区间或 Fisher 检验。

点估计也可以直接用 pandas 从 CSV 得到：

```python
import pandas as pd
s = pd.read_csv("data/samples.csv")
main = s[(s.spec_version == "detailed") & (s.strategy == "zero")]

# 表 4：主配置 pass@1（修复前），按模型 × 层级
print(main.groupby(["model", "level"]).initial_passed.mean().unstack().mul(100).round(1))

# 表 5：严格判据可综合率（全部 300 样本为分母）与意外锁存器率
print(main.groupby("model")[["initial_synthesizable", "initial_unintended_latch"]].mean().mul(100).round(1))

# 图 4：首要错误类型分布（修复前失败样本）
print(main[main.initial_passed == 0].groupby(["level", "initial_primary_error"]).size().unstack(fill_value=0))

# 表 6：Model B 规范完整度 × 提示策略
b = s[s.model == "Model B"]
print(b.groupby(["strategy", "spec_version"]).initial_passed.mean().unstack().mul(100).round(1))

# 图 5：累计通过率随修复轮次
v = pd.read_csv("data/verdicts.csv")
vm = v[(v.spec_version == "detailed") & (v.strategy == "zero")]
cum = vm[vm.passed == 1].groupby(["model", "sample_id"]).round.min().reset_index()
print(cum.groupby("model").round.value_counts().sort_index().groupby(level=0).cumsum().div(3))
```

## 6. 复判数据（`rejudge/`）

两项复判都只针对修复前（第 0 轮）的初始代码，`sample_id` 与本目录其他文件一致。

**编译判据复判**（论文 4.3 节、表 5）。严格判据要求代码先通过以 IEEE 1364-2005 为上限的 Verilator 编译检查，主配置下有 193 个样本止于这一步而没有进入 Vivado。把这 193 份代码逐一送 Vivado 2024.1，流程和判据与平台正式判定相同（out-of-context 综合 + opt/place/route，任一步报 Error 即不接受）：

| 列（`vivado_recheck.csv`） | 含义 |
|---|---|
| `verilator_kind` | Verilator 报错的归类（对线网作过程赋值、重复声明、语法错误等） |
| `icarus_compile`, `icarus_sim_pass` | Icarus Verilog `-g2005` 能否编译；能编译时正式测试台是否通过 |
| `vivado_synth_ok` | Vivado 综合无 Error（57 例） |
| `vivado_impl_ok` | 综合通过者继续实现，无 Error 为 1；7 例因多驱动网络被 DRC（MDRV-1）拒绝。综合未通过者为空 |
| `vivado_accepts` | `vivado_synth_ok` 且 `vivado_impl_ok`（50 例），即论文所说“被 Vivado 接受” |
| `vivado_latch` | 综合报告出现锁存器 |
| `vivado_error`, `vivado_impl_error` | 第一条综合 Error；实现阶段的 DRC 规则号 |

`vivado_recheck_xsim.csv` 给出 57 个综合通过样本在 Vivado 仿真器（xsim）下运行正式测试台的结果：`xsim_stage`（止于 `compile` / `elab` / `sim`）、`xsim_pass`、`xsim_detail`（首条失败信息）、`golden_passes_xsim`（同题黄金模型在 xsim 下通过，全部为 1）。“Vivado 判据下功能亦正确”= `vivado_accepts` 且 `xsim_pass` 且无锁存器（39 例）。

**弱测试台复判**（论文 4.1 节）。`weak_tb_escape_rate.csv` 列出全部配置下被正式测试台判为仿真失败的 L2、L3 样本（1 021 行）在各题弱测试台 `tb_weak.v` 下的结果：`weak_tb_compiled`、`weak_tb_pass`；`primary_error` 为正式测试台给出的首要错误。论文报告的是主配置（`detailed` × `zero`）的 292 例，其中 139 例通过弱测试台。

## 7. 使用说明

- 题库、平台与本数据集均以 MIT 许可证发布。`raw_response` 与 `code` 为各模型 API 的输出，依据各服务商服务条款用户可使用并发布其输出；本数据集中的生成代码**仅供教学与研究**（如实验一的错误归因、实验二的逃逸样本），不保证功能正确。
- 云端模型会迭代版本，`model_version` 与 `created_at` 记录了本次评测的时点；按同一配置重新采样不能得到完全相同的结果，本目录即论文结论的原始依据。
- 重新导出：`vleval export --db results/results.db --out data`（加 `--no-tool-logs` 可省略最大的日志文件）。本目录按现行十类分类规则导出：2026-10 的结果库先经 `vleval reclassify` 迁移（依据存储的判定依据文字逐条转换，不重跑工具；原规则下首要错误留空的 768 条判定与按题型兜底计为 E7 的 800 条判定改为 E10，其余类别不变）。
- 实验二逃逸样本：`vleval escapes --levels L2,L3` 从 `samples.jsonl` 中选出"正式测试台判为仿真失败、弱测试台放过"的生成代码写入各题 `benchmark/<level>/<id>/escapes/`（固定种子，结果已入库；`index.json` 记录每份样本的 `sample_id` 以便回溯到本数据集）。
