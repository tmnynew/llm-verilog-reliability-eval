"""Aggregate stored samples into the paper's tables (Markdown + JSON).

Tables produced (mirroring the manuscript):
  T5  pass@1 / pass@5 by model × level with Wilson 95% CI
  T6  synthesizability: synth rate, unintended-latch rate, E9 rate, lint density
  T7  primary-error distribution by level
  T8  spec version × prompting strategy effect (pass@1 + Fisher vs baseline)
  T9  repair convergence (cumulative pass rate after round 0..3)
  T10 resource ratio vs golden reference (LUT, FF, Fmax)
"""

from __future__ import annotations

import json
import logging
from collections import defaultdict
from collections.abc import Iterable
from pathlib import Path

from .benchmark import Benchmark
from .models import ErrorCode, Level, Sample, SpecVersion, Stage, Strategy
from .stats import cohen_kappa, fisher_exact, pass_at_k, repair_curve, wilson_ci


def _pct(x: float) -> str:
    return f"{100 * x:.1f}"  # one decimal, same precision as the paper's tables


class Report:
    def __init__(
        self,
        samples: Iterable[Sample],
        benchmark: Benchmark,
        baseline_spec: SpecVersion = SpecVersion.DETAILED,
        baseline_strategy: Strategy = Strategy.ZERO_SHOT,
    ):
        self.samples = list(samples)
        self.bench = benchmark
        self.baseline = (baseline_spec, baseline_strategy)
        self.models = sorted({s.model for s in self.samples})
        self.tables: dict[str, str] = {}
        self.data: dict[str, object] = {}

    # ---- helpers ----------------------------------------------------- #
    def _level(self, s: Sample) -> Level:
        return self.bench.get(s.problem_id).level

    def _baseline(self, model: str, level: Level | None = None) -> list[Sample]:
        return [s for s in self.samples if s.model == model and (s.spec_version, s.strategy) == self.baseline and (level is None or self._level(s) == level)]

    @staticmethod
    def _passk(samples: list[Sample], k: int, use_final: bool = False) -> float:
        """Average pass@k over problems (n = samples per problem)."""
        by_problem: dict[str, list[bool]] = defaultdict(list)
        for s in samples:
            by_problem[s.problem_id].append((s.final if use_final else s.initial).passed)
        if not by_problem:
            return 0.0
        return sum(pass_at_k(len(v), sum(v), min(k, len(v))) for v in by_problem.values()) / len(by_problem)

    # ---- tables ------------------------------------------------------ #
    def table_passk(self) -> str:
        rows = ["| 模型 | 层级 | n | pass@1/% | Wilson 95% CI | pass@5/% |", "|---|---|---|---|---|---|"]
        data = {}
        for m in self.models:
            for lv in Level:
                ss = self._baseline(m, lv)
                if not ss:
                    continue
                k = sum(s.initial.passed for s in ss)
                lo, hi = wilson_ci(k, len(ss))
                p1, p5 = self._passk(ss, 1), self._passk(ss, 5)
                rows.append(f"| {m} | {lv.value} | {len(ss)} | {_pct(p1)} | [{_pct(lo)}, {_pct(hi)}] | {_pct(p5)} |")
                data[f"{m}/{lv.value}"] = {"n": len(ss), "pass1": p1, "ci": [lo, hi], "pass5": p5}
        self.data["passk"] = data
        return "\n".join(rows)

    def table_synth(self) -> str:
        rows = [
            "| 模型 | 可综合率/% | 意外锁存器率/% | E9 出现率/% | 仿真通过但综合失败或含锁存器/% | Lint 告警密度 | 工具判定差异率/% |",
            "|---|---|---|---|---|---|---|",
        ]
        data = {}
        for m in self.models:
            ss = self._baseline(m)
            # Paper Table 6 convention: synthesizability / latch / E9 rates use *all* samples of the
            # configuration as denominator (a sample that does not compile is not synthesizable);
            # lint density and tool disagreement are only defined for samples that reached synthesis.
            judged = [s for s in ss if s.initial.stage not in (Stage.INTERFACE, Stage.COMPILE)]
            if not judged:
                continue
            n_all, n_judged = len(ss), len(judged)
            synth = sum(s.initial.synth_ok for s in judged) / n_all
            latch = sum(s.initial.unintended_latch for s in judged) / n_all
            e9 = sum(ErrorCode.E9_SIM_ONLY_CONSTRUCT in s.initial.errors for s in judged) / n_all
            sim_ok = [s for s in judged if s.initial.sim_passed]
            sim_but_synth_bad = sum(not s.initial.synth_ok for s in sim_ok) / len(sim_ok) if sim_ok else 0.0
            dens = [s.initial.lint_density for s in judged if s.initial.lint_density is not None]
            dens_txt = f"{sum(dens) / len(dens):.2f}" if dens else "N/A"
            dis = sum(s.initial.tool_disagreement for s in judged) / n_judged
            rows.append(f"| {m} | {_pct(synth)} | {_pct(latch)} | {_pct(e9)} | {_pct(sim_but_synth_bad)} | {dens_txt} | {_pct(dis)} |")
            data[m] = {"synth": synth, "latch": latch, "e9": e9, "sim_ok_synth_bad": sim_but_synth_bad, "lint_density": dens_txt, "disagreement": dis}
        self.data["synth"] = data
        return "\n".join(rows)

    def table_errors(self) -> str:
        codes = list(ErrorCode)
        rows = ["| 层级 | 失败样本数 | " + " | ".join(c.value for c in codes) + " | 待复核 |", "|---|---|" + "---|" * (len(codes) + 1)]
        data = {}
        for lv in Level:
            failed = [s for m in self.models for s in self._baseline(m, lv) if not s.initial.passed]
            if not failed:
                continue
            counts = {c: sum(s.initial.primary_error == c for s in failed) for c in codes}
            review = sum(s.initial.primary_error is None for s in failed)
            n = len(failed)
            rows.append(f"| {lv.value} | {n} | " + " | ".join(_pct(counts[c] / n) for c in codes) + f" | {_pct(review / n)} |")
            data[lv.value] = {c.value: counts[c] for c in codes} | {"review": review, "n": n}
        self.data["errors"] = data
        return "\n".join(rows)

    def table_prompt_effects(self) -> str:
        rows = ["| 模型 | 规范版本 | 提示策略 | n | pass@1/% | 意外锁存器率/% | Fisher p（vs 详细+零样本） |", "|---|---|---|---|---|---|---|"]
        data = {}
        for m in self.models:
            base = self._baseline(m)
            bk, bn = sum(s.initial.passed for s in base), len(base)
            for spec in SpecVersion:
                for strat in Strategy:
                    ss = [s for s in self.samples if s.model == m and s.spec_version == spec and s.strategy == strat]
                    if not ss:
                        continue
                    k, n = sum(s.initial.passed for s in ss), len(ss)
                    latch = sum(s.initial.unintended_latch for s in ss) / n
                    p = fisher_exact(k, n - k, bk, bn - bk) if bn and (spec, strat) != self.baseline else None
                    ptxt = "—" if p is None else (f"{p:.3f}" if p >= 0.001 else "<0.001")
                    rows.append(f"| {m} | {spec.value} | {strat.value} | {n} | {_pct(k / n)} | {_pct(latch)} | {ptxt} |")
                    data[f"{m}/{spec.value}/{strat.value}"] = {"n": n, "pass1": k / n, "latch": latch, "p": p}
        self.data["prompt"] = data
        return "\n".join(rows)

    def table_repair(self) -> str:
        rows = ["| 模型 | n | 第0轮/% | 第1轮/% | 第2轮/% | 第3轮/% | E1–E6,E9 修复成功率/% | E7/% | E8/% |", "|---|---|---|---|---|---|---|---|---|"]
        data = {}
        for m in self.models:
            ss = self._baseline(m)
            if not ss:
                continue
            r2p = [next((i for i, v in enumerate(s.rounds) if v.passed), -1) for s in ss]
            curve = repair_curve(r2p, max_rounds=3)

            def fix_rate(pred, ss=ss) -> str:
                fs = [s for s in ss if not s.initial.passed and pred(s.initial.primary_error)]
                return _pct(sum(s.final.passed for s in fs) / len(fs)) if fs else "—"

            local = fix_rate(lambda e: e is not None and e not in (ErrorCode.E7_FSM, ErrorCode.E8_PROTOCOL))
            e7 = fix_rate(lambda e: e == ErrorCode.E7_FSM)
            e8 = fix_rate(lambda e: e == ErrorCode.E8_PROTOCOL)
            rows.append(f"| {m} | {len(ss)} | " + " | ".join(_pct(c) for c in curve) + f" | {local} | {e7} | {e8} |")
            data[m] = {"curve": curve, "local": local, "e7": e7, "e8": e8}
        self.data["repair"] = data
        return "\n".join(rows)

    def table_resources(self) -> str:
        rows = ["| 模型 | 层级 | 通过样本数 | LUT 比值（中位数） | FF 比值（中位数） | Fmax 比值（中位数） |", "|---|---|---|---|---|---|"]
        for m in self.models:
            for lv in Level:
                ratios: dict[str, list[float]] = defaultdict(list)
                passed = [s for s in self._baseline(m, lv) if s.final.passed and s.final.resources]
                for s in passed:
                    ref = self.bench.get(s.problem_id).reference_resources
                    for key in ("LUT", "FF", "Fmax_MHz"):
                        if key in ref and key in s.final.resources and ref[key]:
                            ratios[key].append(s.final.resources[key] / ref[key])
                if not passed:
                    continue

                def med(v: list[float]) -> str:
                    if not v:
                        return "N/A"
                    v = sorted(v)
                    return f"{v[len(v) // 2]:.2f}"

                rows.append(f"| {m} | {lv.value} | {len(passed)} | {med(ratios['LUT'])} | {med(ratios['FF'])} | {med(ratios['Fmax_MHz'])} |")
        return "\n".join(rows)

    def kappa(self, annotations: list[tuple]) -> float | None:
        """Cohen's kappa between the first two raters found in the annotation table."""
        by_sample: dict[int, dict[str, str]] = defaultdict(dict)
        for sid, rater, code in annotations:
            by_sample[sid][rater] = code or "NONE"
        raters = sorted({r for d in by_sample.values() for r in d})
        if len(raters) < 2:
            return None
        a, b = raters[:2]
        pairs = [(d[a], d[b]) for d in by_sample.values() if a in d and b in d]
        if not pairs:
            return None
        return cohen_kappa([p[0] for p in pairs], [p[1] for p in pairs])

    # ---- driver ------------------------------------------------------ #
    def build(self) -> dict[str, str]:
        self.tables = {
            "T5_passk": self.table_passk(),
            "T6_synth": self.table_synth(),
            "T7_errors": self.table_errors(),
            "T8_prompt": self.table_prompt_effects(),
            "T9_repair": self.table_repair(),
            "T10_resources": self.table_resources(),
        }
        return self.tables

    def write(self, out_dir: Path) -> None:
        out_dir.mkdir(parents=True, exist_ok=True)
        if not self.tables:
            self.build()
        md = [f"# 评测结果汇总（样本数 {len(self.samples)}，模型 {', '.join(self.models)}）\n"]
        for name, table in self.tables.items():
            md.append(f"## {name}\n\n{table}\n")
        (out_dir / "tables.md").write_text("\n".join(md), encoding="utf-8")
        (out_dir / "summary.json").write_text(json.dumps(self.data, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
        try:
            from .figures import draw_all
        except ImportError:
            return  # matplotlib is optional
        try:
            draw_all(self, out_dir)
        except Exception as e:  # figures must never block the tables
            logging.getLogger("vleval.report").warning("figure generation failed: %s", e)
