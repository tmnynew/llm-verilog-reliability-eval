"""
论文《大模型生成 Verilog 代码可靠性评估实验设计》图 1～图 6 生成脚本。

图 1、图 2 为示意图；图 3～图 6 的数据读取 ``data/report/paper_data.json``
（由 ``scripts/paper_stats.py`` 从结果库统计生成），不含任何占位数据。

    python scripts/make_paper_figures.py [--data data/report/paper_data.json] [--out figures]

输出 300 dpi PNG。需要中文字体（SimHei / Microsoft YaHei；Linux 可安装 Noto Sans CJK 后修改 rcParams）。
"""
import argparse
import json
import os

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Polygon  # noqa: E402

#plt.rcParams["font.sans-serif"] = ["SimHei", "Microsoft YaHei"]
plt.rcParams["font.sans-serif"] = ["SimSun","Times New Roman"]
plt.rcParams["axes.unicode_minus"] = False
plt.rcParams["font.size"] = 9

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ap = argparse.ArgumentParser()
_ap.add_argument("--data", default=os.path.join(_ROOT, "data", "report", "paper_data.json"))
_ap.add_argument("--out", default=os.path.join(_ROOT, "figures"))
_args = _ap.parse_args()
DATA_PATH, OUT = _args.data, _args.out
os.makedirs(OUT, exist_ok=True)
DPI = 300
GRAYS = ["#2b2b2b", "#6e6e6e", "#a8a8a8", "#dcdcdc"]
GRAYS1 = ["#bfbfbf", "#404040", "#2ca02c", "#d62728"]
HATCH = ["", "////", "\\\\", "xx"]

MODEL_LABELS = ["模型A DeepSeek-V4-Pro", "模型B Qwen3-Coder-Plus", "模型C GLM-5", "模型D Qwen3-Coder-30B-A3B"]
LEVELS = ["L1 组合逻辑", "L2 时序逻辑", "L3 系统级"]
STRATEGY_LABELS = {"zero": "零样本", "few": "少样本", "constraint": "编码约束", "cot": "思维链"}
ERR_LABELS = {"E1": "E1接口", "E2": "E2语言子集", "E3": "E3赋值语义", "E4": "E4复位", "E5": "E5位宽",
              "E6": "E6锁存器", "E7": "E7状态机", "E8": "E8协议", "E9": "E9仿真专用结构", "待复核": "待复核"}


def load_data():
    with open(DATA_PATH, encoding="utf-8") as f:
        return json.load(f)


def save(fig, name, retries=5):
    """保存 PNG；文件被预览程序短暂占用时（Windows 下 OSError 22）等待后重试。"""
    import time
    path = os.path.join(OUT, name)
    for k in range(retries):
        try:
            fig.savefig(path, dpi=DPI, bbox_inches="tight")
            return
        except OSError:
            if k == retries - 1:
                raise
            time.sleep(1.0)


def wilson(p_pct, n, z=1.96):
    p = np.asarray(p_pct, float) / 100.0
    n = np.asarray(n, float)
    den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den
    h = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return (p - (c - h)) * 100, ((c + h) - p) * 100


def box(ax, xy, w, h, text, fc="white", lw=1.0, fs=9, style="round,pad=0.02,rounding_size=0.08", bold=False):
    ax.add_patch(FancyBboxPatch(xy, w, h, boxstyle=style, fc=fc, ec="black", lw=lw))
    ax.text(xy[0] + w / 2, xy[1] + h / 2, text, ha="center", va="center", fontsize=fs,
            fontweight="bold" if bold else "normal", linespacing=1.4)


def arrow(ax, p0, p1, lw=1.0, style="-|>", mut=10):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle=style, mutation_scale=mut, lw=lw, color="black"))


def diamond(ax, cx, cy, w, h, text, fs=8.5):
    ax.add_patch(Polygon([(cx - w / 2, cy), (cx, cy + h / 2), (cx + w / 2, cy), (cx, cy - h / 2)],
                         closed=True, fc="white", ec="black", lw=1.0))
    ax.text(cx, cy, text, ha="center", va="center", fontsize=fs, linespacing=1.3)


# ----------------------------- 图1 实验总体方案 -----------------------------
def fig1_overview():
    fig, ax = plt.subplots(figsize=(7.4, 4.8))
    ax.set_xlim(0, 100); ax.set_ylim(0, 60); ax.axis("off")
    box(ax, (28, 52), 44, 6.5, "被测大模型（可插拔，记录版本号与评测日期）\n云端通用模型 / 代码专用模型 / 开源权重模型", fc="#f2f2f2", fs=8.3)

    box(ax, (2, 8), 22, 40, "", fc="#fafafa")
    ax.text(13, 45, "分级评测题库", ha="center", va="center", fontsize=9.5, fontweight="bold")
    items = ["L1 组合 / L2 时序 /\nL3 系统级，各 10 题", "功能规范\n（简略版 / 详细版）", "黄金参考模型\n（上板验证）",
             "测试台\n（穷举 / 周期级 / 事务级）", "变异体集合\n（校验测试台）"]
    y = 41.5
    for t in items:
        box(ax, (4, y - 5.8), 18, 5.8, t, fs=7.5, style="square,pad=0.02")
        y -= 6.6

    box(ax, (28, 8), 44, 40, "", fc="#fafafa")
    ax.text(50, 45, "自动化评估平台", ha="center", va="center", fontsize=9.5, fontweight="bold")
    steps = ["提示构造（规范完整度 × 提示策略）", "模型调用（T=0.2，n=10 次采样）", "代码提取、接口检查、编译+Lint（Verilator）",
             "功能仿真（Icarus Verilog）", "综合判定（Vivado OOC，Yosys 预筛）", "指标汇总 + 置信区间"]
    y = 41.5
    cy = []
    for t in steps:
        h = 4.2
        box(ax, (30, y - h), 32, h, t, fs=6.6 if len(t) > 18 else 7.4, style="square,pad=0.02")
        cy.append((y - h / 2, h))
        y -= h + 0.9
    for (a, ha), (b, hb) in zip(cy[:-1], cy[1:]):
        arrow(ax, (46, a - ha / 2), (46, b + hb / 2), mut=8)
    # 修复环：接口/编译、仿真、综合三个判定环节的失败样本 → 错误反馈修复 → 回到模型调用
    rx0, rw = 64.5, 6.5
    rtop, rbot = cy[2][0] + 2.4, cy[4][0] - 2.4
    box(ax, (rx0, rbot), rw, rtop - rbot, "错误\n反馈\n修复\n≤3 轮", fs=7.2, fc="#eeeeee")
    for k in (2, 3, 4):  # 三类失败分支输入
        arrow(ax, (62, cy[k][0]), (rx0, cy[k][0]), mut=7)
    rxc = rx0 + rw / 2
    ax.text(rxc, rbot - 1.4, "失败样本+错误信息", fontsize=5.6, ha="center", va="center")
    arrow(ax, (rxc, rtop), (rxc, cy[1][0]), style="-", mut=1)  # 输出：修复提示回到模型调用
    arrow(ax, (rxc, cy[1][0]), (62, cy[1][0]), mut=7)
    ax.text(rxc + 0.4, cy[1][0] + 1.0, "修复提示", fontsize=6, ha="center")

    box(ax, (76, 8), 22, 40, "", fc="#fafafa")
    ax.text(87, 45, "分层实验内容", ha="center", va="center", fontsize=9.5, fontweight="bold")
    levels = ["实验一 基础\n代码审查与错误归因", "实验二 提高\n测试台增强\n（杀死存活变异体）", "实验三 提高\n规范完整度 ×\n提示策略对比",
              "实验四 综合\n多轮修复 + 上板\n+ 资源/时序分析"]
    y = 41.5
    for t in levels:
        h = 6.0 if t.count("\n") == 1 else 8.0
        box(ax, (78, y - h), 18, h, t, fs=7.4, style="square,pad=0.02")
        y -= h + 0.8

    arrow(ax, (24, 28), (28, 28)); ax.text(26, 29.6, "题目", ha="center", fontsize=7.5)
    arrow(ax, (72, 28), (76, 28)); ax.text(74, 29.6, "指标", ha="center", fontsize=7.5)
    arrow(ax, (50, 52), (50, 48)); ax.text(51.5, 49.5, "API", fontsize=7.5)
    box(ax, (2, 0.5), 22, 5, "教师：维护题库、标注与复核", fs=7.5, style="square,pad=0.02")
    box(ax, (28, 0.5), 44, 5, "学生：审查代码、编写激励与断言、设计提示、上板验证", fs=7.5, style="square,pad=0.02")
    arrow(ax, (13, 5.5), (13, 8), mut=8)
    arrow(ax, (50, 5.5), (50, 8), mut=8)
    save(fig, "fig1_overview.png")
    plt.close(fig)


# ----------------------------- 图2 单样本评估流程 -----------------------------
def fig2_pipeline():
    fig, ax = plt.subplots(figsize=(4.8, 8.0))
    ax.set_xlim(0, 68); ax.set_ylim(0, 120); ax.axis("off")
    cx, bw = 26, 34
    x0, x1 = cx - bw / 2, cx + bw / 2
    sq = "square,pad=0.02"; rd = "round,pad=0.02,rounding_size=0.6"
    box(ax, (cx - 13, 114), 26, 5, "开始：选择题目 / 模型 / 配置", fs=8, style=rd)
    box(ax, (x0, 104), bw, 6, "构造提示词\n（功能规范版本 + 提示策略模板）", fs=8, style=sq)
    box(ax, (x0, 94), bw, 6, "调用模型生成\n（T=0.2，第 i 个样本，回复缓存）", fs=8, style=sq)
    box(ax, (x0, 84), bw, 6, "提取代码块，检查模块名 / 端口 / 位宽；\nVerilator 编译检查 + Lint（1364-2005）", fs=7.4, style=sq)
    diamond(ax, cx, 76, 28, 8, "接口正确\n且可编译？", fs=8)
    box(ax, (x0, 60), bw, 6, "Icarus Verilog 功能仿真\n（与测试台联合，超时 60 s）", fs=8, style=sq)
    diamond(ax, cx, 52, 28, 8, "全部用例通过？")
    box(ax, (x0, 36), bw, 6, "Vivado OOC 综合 + 实现判定\n（Yosys 预筛；取 LUT/FF/WNS，查锁存器）", fs=7.4, style=sq)
    diamond(ax, cx, 28, 28, 8, "无综合错误\n且无意外锁存器？", fs=8)
    box(ax, (x0, 10), bw, 7, "记录指标：通过状态、首要错误类型、\nLint 密度、LUT/FF/Fmax、修复轮次", fs=7.8, style=sq)
    box(ax, (cx - 13, 1), 26, 5, "结束：写入数据库", fs=8, style=rd)
    for y0, y1 in [(114, 110), (104, 100), (94, 90), (84, 80), (72, 66), (60, 56), (48, 42), (36, 32), (24, 17), (10, 6)]:
        arrow(ax, (cx, y0), (cx, y1), mut=8)
    for y in (69, 45, 20.5):
        ax.text(cx + 1.2, y, "是", fontsize=7.5)

    rx = 53
    box(ax, (rx - 7, 46), 14, 12, "构造修复提示\n（附接口差异 /\n编译错误 / 失败用例 /\n综合错误信息）", fs=7.1, fc="#eeeeee", style=sq)
    diamond(ax, rx, 76, 14, 8, "轮次 < 3？", fs=7.5)
    xv = rx - 8.5
    arrow(ax, (cx + 14, 76), (xv, 76), style="-", mut=1); ax.text(40.6, 77.2, "否", fontsize=7.5)
    arrow(ax, (xv, 76), (xv, 52), style="-", mut=1)
    arrow(ax, (xv, 52), (rx - 7, 52), mut=8)
    arrow(ax, (cx + 14, 52), (xv, 52), style="-", mut=1); ax.text(40.6, 53.2, "否", fontsize=7.5)
    arrow(ax, (cx + 14, 28), (rx, 28), style="-", mut=1); ax.text(40.6, 29.2, "否", fontsize=7.5)
    arrow(ax, (rx, 28), (rx, 46), mut=8)
    arrow(ax, (rx, 58), (rx, 72), mut=8)
    arrow(ax, (rx, 80), (rx, 97), style="-", mut=1); ax.text(rx + 1.2, 88, "是", fontsize=7.5)
    arrow(ax, (rx, 97), (x1, 97), mut=8)
    arrow(ax, (rx + 7, 76), (64, 76), style="-", mut=1); ax.text(61, 77.2, "否", fontsize=7.5)
    arrow(ax, (64, 76), (64, 13.5), style="-", mut=1)
    arrow(ax, (64, 13.5), (x1, 13.5), mut=8)
    ax.text(65.2, 44, "记为失败（含首要错误类型）", fontsize=7, rotation=90, va="center")
    save(fig, "fig2_pipeline.png")
    plt.close(fig)


# ----------------------------- 图3 pass@k（含 Wilson 95% CI） -----------------------------
def fig3_passk(d):
    pass1, pass5, n = np.array(d["pass1"]), np.array(d["pass5"]), np.array(d["n_per_level"])
    fig, ax = plt.subplots(figsize=(6.4, 3.3))
    n_m, n_l = pass1.shape
    width = 0.1
    x = np.arange(n_l)
    for i in range(n_m):
        off = (i - (n_m - 1) / 2) * (2 * width + 0.02)
        lo, hi = wilson(pass1[i], n[i])
        # pass@1：实心
 
        ax.bar(x + off - width / 2, pass1[i], width, color=GRAYS[i], edgecolor="black", lw=0.5,
               yerr=[lo, hi], capsize=1.5, error_kw={"lw": 0.6}, label=f"{MODEL_LABELS[i]} pass@1")
        ax.bar(x + off + width / 2, pass5[i], width, color="white", edgecolor="black", lw=0.5,
               hatch=HATCH[i], label=f"{MODEL_LABELS[i]} pass@5")
    ax.set_xticks(x); ax.set_xticklabels(LEVELS)
    ax.set_ylabel("通过率 / %"); ax.set_ylim(0, 108)
    ax.grid(axis="y", ls=":", lw=0.5); ax.set_axisbelow(True)
    ax.tick_params(axis='both', direction='in', length=3, width=0.6,)
    ax.legend(ncol=2, fontsize=6.5, frameon=False, loc="upper center", bbox_to_anchor=(0.5, -0.12))
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    save(fig, "fig3_passk.png")
    plt.close(fig)


# ----------------------------- 图4 首要错误类型分布 -----------------------------
def fig4_error_dist(d):
    dist = np.array(d["err_dist"])  # level x code
    codes = d["err_codes"]
    fig, ax = plt.subplots(figsize=(6.4, 3.4))
    x = np.arange(len(LEVELS)); bottom = np.zeros(len(LEVELS))
    colors = plt.cm.Greys(np.linspace(0.12, 0.9, len(codes) - 1)).tolist() + ["white"]
    for j, code in enumerate(codes):
        vals = dist[:, j]
        if vals.sum() == 0:
            continue
        ax.bar(x, vals, 0.55, bottom=bottom, color=colors[j], edgecolor="black", lw=0.5,
               hatch="//" if code == "待复核" else "", label=ERR_LABELS[code])
        for i, v in enumerate(vals):
            if v >= 8:
                ax.text(x[i], bottom[i] + v / 2, f"{v:.0f}", ha="center", va="center", fontsize=7,
                        color="white" if (j >= 5 and code != "待复核") else "black")
        bottom += vals
    labels = [f"{lv}\n(n={n})" for lv, n in zip(LEVELS, d["err_n"])]
    ax.set_xticks(x); ax.set_xticklabels(labels)
    ax.tick_params(axis='both', direction='in', length=3, width=0.6,)
    ax.set_ylabel("失败样本中占比 / %"); ax.set_ylim(0, 100)
    ax.legend(bbox_to_anchor=(1.01, 1), loc="upper left", fontsize=7, frameon=False)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    save(fig, "fig4_error_dist.png")
    plt.close(fig)


# ----------------------------- 图5 规范完整度 × 提示策略 -----------------------------
def fig5_prompt(d):
    brief, full = np.array(d["prompt_brief"]), np.array(d["prompt_detailed"])
    n_b, n_f = d["prompt_n"]
    strategies = [STRATEGY_LABELS[s] for s in d["strategies"]]
    fig, ax = plt.subplots(figsize=(5.2, 3.0))
    x = np.arange(len(strategies)); w = 0.34
    lo1, hi1 = wilson(brief, n_b); lo2, hi2 = wilson(full, n_f)
    b1 = ax.bar(x - w / 2, brief, w, color=GRAYS1[1], edgecolor=GRAYS1[1], lw=0.6, yerr=[lo1, hi1], capsize=1.8,error_kw={"lw": 0.5}, label="简略规范")
    b2 = ax.bar(x + w / 2, full, w, color=GRAYS1[0], edgecolor=GRAYS1[0], lw=0.6, yerr=[lo2, hi2], capsize=1.8,error_kw={"lw": 0.5}, label="详细规范")
    for b in list(b1) + list(b2):
        ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 6, f"{b.get_height():.1f}", ha="center", fontsize=7)
    ax.set_xticks(x); ax.set_xticklabels(strategies); ax.set_xlabel("提示策略")
    ax.set_ylabel("pass@1（修复前）/ %"); ax.set_ylim(0, 100)
    ax.tick_params(axis='both', direction='in', length=3, width=0.6,)
    ax.grid(axis="y", ls=":", lw=0.5); ax.set_axisbelow(True)
    ax.legend(frameon=False, fontsize=8, loc="upper left")
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    save(fig, "fig5_prompt.png")
    plt.close(fig)


# ----------------------------- 图6 多轮修复收敛曲线 -----------------------------
def fig6_repair(d):
    """(a) 主配置全体样本累计通过率；(b) L3 题累计通过率。数据分别来自 repair_all / repair_L3。"""
    rounds = [0, 1, 2, 3]
    fig, axes = plt.subplots(1, 2, figsize=(7.4, 3.1))
    markers = ["o", "s", "^", "D"]
    panels = [("repair_all", "全体样本累计通过率 / %", "(a) 主配置全体样本（n=300/模型）"),
              ("repair_L3", "L3 题累计通过率 / %", "(b) L3 系统级题（n=100/模型）")]
    for ax, (key, ylab, title) in zip(axes, panels):
        for i, m in enumerate(d["models"]):
            ys = d[key][m]
            ax.plot(rounds, ys, marker=markers[i], color=GRAYS[min(i, 2)], ls=["-", "-", "--", ":"][i],
                    lw=1.2, ms=5, label=MODEL_LABELS[i])
            for k, (xx, yy) in enumerate(zip(rounds, ys)):
                # 数值标注的上下位置按曲线相对关系错开，避免重叠（+6 在上，-11 在下）
                dx = 0
                if key == "repair_all":
                    dy = {0: 6, 1: -11, 2: -11, 3: 6}[i]
                    if i == 2 and k > 0:   # C 夹在 A、B 之间，标注放到右侧
                        dx, dy = 11, -3
                else:
                    if i == 0:
                        dy = 6 if k == 0 else -11
                    elif i == 2:
                        dy = -11 if k == 0 else 6
                    else:
                        dy = {1: 6, 3: -11}[i]
                ax.annotate(f"{yy:.0f}", (xx, yy), textcoords="offset points", xytext=(dx, dy), ha="center", fontsize=6.8)
        ax.set_xticks(rounds); ax.set_xticklabels(["0（修复前）", "1", "2", "3"])
        ax.set_xlabel("修复轮次"); ax.set_ylabel(ylab); ax.set_ylim(0, 100)
        ax.set_title(title, fontsize=8.5, pad=4)
        ax.grid(ls=":", lw=0.5); ax.set_axisbelow(True)
        ax.tick_params(axis='both', direction='in', length=3, width=0.6)
        ax.spines['top'].set_visible(False); ax.spines['right'].set_visible(False)
    axes[0].legend(frameon=False, fontsize=7, loc="lower right")
    axes[1].legend(frameon=False, fontsize=7, loc="upper left")
    fig.tight_layout(w_pad=1.5)
    save(fig, "fig6_repair.png")
    plt.close(fig)


if __name__ == "__main__":
    fig1_overview(); fig2_pipeline()
    d = load_data()
    fig3_passk(d); fig4_error_dist(d); fig5_prompt(d); fig6_repair(d)
    print("done:", OUT)
