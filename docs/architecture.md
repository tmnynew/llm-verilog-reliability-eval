# 平台架构（Architecture）

```
                 ┌──────────────┐    ┌──────────────┐
  configs/*.yaml │  prompting   │    │     llm      │  OpenAI 兼容 API / vLLM
  templates/*.md │ spec×策略→msg│───▶│ client+cache │───────────────┐
                 └──────────────┘    └──────────────┘               │
                                                                     ▼
 benchmark/ ──▶ benchmark.py ──▶ runner.py ──▶ extract.py ──▶ judge.py ──▶ taxonomy.py ──▶ db.py
 (题库)          (加载/校验)      (生成/修复循环)  (提码/接口)    │                (E1–E9)      (SQLite)
                                                                 │                                  │
                                                       tools/simulators.py  tools/synth.py          ▼
                                                       Verilator / Icarus   Yosys / Vivado     report.py
                                                                                                figures.py
 mutation.py ──▶ benchmark/*/mutants/  (变异体生成与变异得分)                                    (表 5–10, 图)
 web/app.py     (学生 Web 界面：提交代码、查看判定；不接触 API 密钥)
 cli.py         (vleval 命令行入口)
```

## 分层与依赖方向

| 层 | 模块 | 依赖 | 说明 |
|---|---|---|---|
| 领域模型 | `models.py` | — | 枚举（层级、阶段、错误码、策略）、`Problem`/`Sample`/`Verdict` 数据类；所有层共用，防止 CLI、判定器和报表漂移 |
| 题库 | `benchmark.py` | models | 目录约定、静态校验（禁用词、必需文件） |
| 工具封装 | `tools/` | models | 每个 EDA 工具一个薄封装，统一返回 `ToolResult`；超时、找不到工具都不抛异常 |
| 静态分析 | `extract.py` | models | 提取代码块、解析模块头、接口检查、E2/E9 静态线索 |
| 分类 | `taxonomy.py` | models | 纯函数 `classify(Evidence) -> Classification`，只依据可观察证据 |
| 判定 | `judge.py` | tools, extract, taxonomy | 图 2 流程；每个样本独立临时目录，可并行 |
| 生成 | `prompting.py`, `llm.py` | models | 模板外置；响应缓存保证课堂零 API 调用 |
| 编排 | `runner.py` | judge, llm, prompting, db | 配置乘积、修复循环、断点续跑 |
| 持久化 | `db.py` | models | 扁平 SQLite，便于教师直接查询、导出 JSONL |
| 报表 | `report.py`, `figures.py`, `stats.py` | db, benchmark | 论文各表；Wilson CI、Fisher、Kappa |
| 变异测试 | `mutation.py` | models | 词法级一阶变异；等价变异体人工确认后剔除 |
| 界面 | `cli.py`, `web/` | 全部 | 命令行与 FastAPI |

## 关键设计决策

1. **证据驱动的分类**：`taxonomy.classify` 只根据测试台标签、Lint 类别、综合报告和静态线索给出候选类别；证据不足时 `needs_review=True`，首要错误留空，交给两名教师复核（`vleval annotate`，Kappa 由 `vleval report` 计算）。这与论文 2.4 节"避免主观判断"的要求一致。
2. **Vivado 权威、Yosys 预筛**：两者都启用时以 Vivado 为准并记录"工具判定差异率"；仅有 Yosys 时（CI、学生交互）结果标记为预筛。
3. **可复现性**：LLM 响应按（模型、消息、温度、样本序号）哈希缓存；仿真随机种子固定；变异体生成确定性（种子 + 轮询算子族）。
4. **单样本隔离**：每次判定在独立临时目录中执行，失败不影响其他样本；`Runner` 用线程池并行（EDA 工具是子进程，GIL 不是瓶颈）。
5. **题库即数据**：题目全部是数据文件，新增题目不改代码；`status: planned` 允许新增题目先入清单、后实现，使清单与已实现子集在同一文件中可追踪（论文表 2 的 30 题当前全部为 `ready`）。


