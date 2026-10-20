"""Black-and-white-friendly figures generated from :class:`vleval.report.Report`."""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from .models import ErrorCode, Level  # noqa: E402

plt.rcParams["font.sans-serif"] = ["SimHei", "Microsoft YaHei", "Noto Sans CJK SC", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False
GRAYS = ["#2b2b2b", "#6e6e6e", "#a8a8a8", "#dcdcdc"]
HATCH = ["", "//", "..", "xx"]


def fig_passk(report, out: Path) -> None:
    data = report.data.get("passk") or {}
    if not data:
        return
    fig, ax = plt.subplots(figsize=(6.5, 3.2), dpi=300)
    levels = [lv.value for lv in Level]
    w = 0.8 / max(1, len(report.models))
    for i, m in enumerate(report.models):
        vals = [100 * data.get(f"{m}/{lv}", {}).get("pass1", 0) for lv in levels]
        err = [
            (
                max(0.0, 100 * (data[f"{m}/{lv}"]["pass1"] - data[f"{m}/{lv}"]["ci"][0])),
                max(0.0, 100 * (data[f"{m}/{lv}"]["ci"][1] - data[f"{m}/{lv}"]["pass1"])),
            )
            if f"{m}/{lv}" in data
            else (0, 0)
            for lv in levels
        ]
        xs = [j + (i - (len(report.models) - 1) / 2) * w for j in range(len(levels))]
        ax.bar(
            xs,
            vals,
            w * 0.95,
            color=GRAYS[i % 4],
            hatch=HATCH[i % 4],
            edgecolor="black",
            label=m,
            yerr=[[e[0] for e in err], [e[1] for e in err]],
            capsize=2,
            error_kw={"lw": 0.8},
        )
    ax.set_xticks(range(len(levels)))
    ax.set_xticklabels(["L1 组合逻辑", "L2 时序逻辑", "L3 系统级"])
    ax.set_ylabel("pass@1 / %")
    ax.set_ylim(0, 100)
    ax.legend(ncol=len(report.models), loc="upper center", bbox_to_anchor=(0.5, -0.15), frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(out / "fig_passk.png")
    plt.close(fig)


def fig_errors(report, out: Path) -> None:
    data = report.data.get("errors") or {}
    if not data:
        return
    fig, ax = plt.subplots(figsize=(6.5, 3.0), dpi=300)
    codes = [c.value for c in ErrorCode]
    levels = list(data.keys())
    bottoms = [0.0] * len(levels)
    for i, c in enumerate(codes):
        vals = [100 * data[lv][c] / data[lv]["n"] for lv in levels]
        ax.barh(levels, vals, left=bottoms, color=GRAYS[i % 4] if i % 2 == 0 else "white", hatch=HATCH[i % 4], edgecolor="black", label=c)
        bottoms = [b + v for b, v in zip(bottoms, vals, strict=True)]
    ax.set_xlabel("首要错误占比 / %")
    ax.legend(ncol=5, loc="upper center", bbox_to_anchor=(0.5, -0.2), frameon=False, fontsize=7)
    fig.tight_layout()
    fig.savefig(out / "fig_errors.png")
    plt.close(fig)


def fig_repair(report, out: Path) -> None:
    data = report.data.get("repair") or {}
    if not data:
        return
    fig, ax = plt.subplots(figsize=(5.5, 3.0), dpi=300)
    markers = ["o", "s", "^", "D"]
    for i, (m, d) in enumerate(data.items()):
        ax.plot(range(4), [100 * v for v in d["curve"]], marker=markers[i % 4], color=GRAYS[min(i, 2)], label=m, lw=1.2)
    ax.set_xticks(range(4))
    ax.set_xlabel("修复轮次")
    ax.set_ylabel("累计通过率 / %")
    ax.set_ylim(0, 100)
    ax.grid(axis="y", ls=":", lw=0.5)
    ax.legend(frameon=False, fontsize=8, loc="lower right")
    fig.tight_layout()
    fig.savefig(out / "fig_repair.png")
    plt.close(fig)


def draw_all(report, out: Path) -> None:
    fig_passk(report, out)
    fig_errors(report, out)
    fig_repair(report, out)
