"""Aggregate stored samples into the paper's tables (Markdown + JSON).

Tables produced (numbering follows the manuscript):
  T4_passk     pass@1 with problem-clustered bootstrap 95% CI, pass@5, by model × level (Table 4)
  T4_tests     level-vs-level and model-vs-model permutation tests on problem pass rates (§4.2)
  T5_synth     synthesizability under the strict criterion; with re-judging data also the Vivado
               criterion and its effect on pass@1 (Table 5, §4.3)
  F4_errors    primary-error distribution by level, ten categories (Fig. 4, §4.4)
  T6_prompt    specification completeness × prompting strategy, paired tests (Table 6, §4.5)
  F5_repair    cumulative pass rate after repair round 0..3 and repair success by primary error (Fig. 5, §4.6)
  resources    LUT / FF / Fmax ratio vs the golden reference (§4.6)
  problems     per-problem passes by model and primary errors by problem (numbers quoted in the text)
  weak_tb      share of full-testbench failures that pass the weak testbench (§4.1; needs re-judging data)

Statistics take the *problem* as the unit of analysis because the samples of one problem are not
independent (§1.2).  All figures are for the baseline configuration (detailed spec × zero-shot) and
the pre-repair round unless stated otherwise.
"""

from __future__ import annotations

import csv
import json
import logging
from collections import Counter, defaultdict
from collections.abc import Callable, Iterable
from fractions import Fraction
from itertools import combinations
from pathlib import Path

from .benchmark import Benchmark
from .models import ErrorCode, Level, Sample, SpecVersion, Stage, Strategy
from .stats import PAPER_SEED, cluster_bootstrap_ci, cohen_kappa, paired_signflip_p, pass_at_k, repair_curve, two_sample_permutation_p

log = logging.getLogger("vleval.report")


def _pct(x: float) -> str:
    return f"{100 * x:.1f}"  # one decimal, same precision as the paper's tables


def _p(p: float | None) -> str:
    if p is None:
        return "—"
    return "<0.001" if p < 0.001 else f"{p:.3f}"


def _passed0(s: Sample) -> bool:
    return s.initial.passed


class Rejudge:
    """Re-judging results shipped in ``data/rejudge`` (see data/README.md, section 6).

    ``vivado_ok``      compile-stage failures that Vivado accepts: synthesis *and* implementation finish without
                       error, i.e. the same flow and the same rule as the regular judging (a design that synthesises
                       but fails the implementation DRC, e.g. on a multiply driven net, is not accepted)
    ``vivado_pass``    of these, the ones that also pass the full testbench under the Vivado simulator, latch-free
    ``weak``           sample_id → passes the weak testbench (full-testbench simulation failures, L2/L3)
    """

    def __init__(self, directory: Path):
        self.vivado_ok: set[int] = set()
        self.vivado_pass: set[int] = set()
        self.weak: dict[int, bool] = {}
        self.available = False
        self._xsim_pass: set[int] = set()
        d = Path(directory)
        for name, fn in (("vivado_recheck.csv", self._synth), ("vivado_recheck_xsim.csv", self._xsim), ("weak_tb_escape_rate.csv", self._weak)):
            if (d / name).exists():
                with open(d / name, encoding="utf-8-sig", newline="") as f:
                    for row in csv.DictReader(f):
                        fn(row)
                self.available = True
        self.vivado_pass = self._xsim_pass & self.vivado_ok

    def _synth(self, r: dict) -> None:
        # files written before the implementation step was added have no vivado_impl_ok column
        if r["vivado_synth_ok"] == "1" and r.get("vivado_impl_ok", "1") == "1":
            self.vivado_ok.add(int(r["sample_id"]))

    def _xsim(self, r: dict) -> None:
        if r["xsim_pass"] == "1" and r["vivado_latch"] == "0":
            self._xsim_pass.add(int(r["sample_id"]))

    def _weak(self, r: dict) -> None:
        self.weak[int(r["sample_id"])] = r["weak_tb_pass"] == "1"


class Report:
    def __init__(
        self,
        samples: Iterable[Sample],
        benchmark: Benchmark,
        baseline_spec: SpecVersion = SpecVersion.DETAILED,
        baseline_strategy: Strategy = Strategy.ZERO_SHOT,
        rejudge: Rejudge | None = None,
        pool: list[str] | None = None,
    ):
        self.samples = list(samples)
        self.bench = benchmark
        self.baseline = (baseline_spec, baseline_strategy)
        self.models = sorted({s.model for s in self.samples})
        self.rejudge = rejudge if rejudge is not None and rejudge.available else None
        #: models reported together in the repair / resource tables (the paper pools its three cloud models)
        self.pool = [m for m in (pool or []) if m in self.models]
        self.tables: dict[str, str] = {}
        self.data: dict[str, object] = {}
        self._level = {pid: benchmark.get(pid).level for pid in {s.problem_id for s in self.samples}}
        self._pids = sorted({s.problem_id for s in self.samples}, key=lambda p: (self._level[p].value, p))
        self._rng = None

    # ---- helpers ----------------------------------------------------- #
    def _config(self, model: str, spec: SpecVersion, strategy: Strategy, level: Level | None = None) -> list[Sample]:
        return [s for s in self.samples if s.model == model and s.spec_version == spec and s.strategy == strategy and (level is None or self._level[s.problem_id] == level)]

    def _baseline(self, model: str, level: Level | None = None) -> list[Sample]:
        return self._config(model, *self.baseline, level=level)

    def _groups(self) -> list[tuple[str, list[str]]]:
        """Model groups for the repair / resource tables: the pool (if any), then every model."""
        groups = [(m, [m]) for m in self.models]
        if len(self.pool) > 1:
            groups.insert(0, ("合并（" + "、".join(self.pool) + "）", self.pool))
        return groups

    @staticmethod
    def _by_problem(samples: list[Sample], ok: Callable[[Sample], bool] = _passed0) -> dict[str, tuple[int, int]]:
        acc: dict[str, list[int]] = defaultdict(lambda: [0, 0])
        for s in samples:
            acc[s.problem_id][0] += bool(ok(s))
            acc[s.problem_id][1] += 1
        return {pid: (k, n) for pid, (k, n) in acc.items()}

    def _rates(self, samples: list[Sample], ok: Callable[[Sample], bool] = _passed0) -> dict[str, Fraction]:
        """Per-problem pass rate, problems in (level, id) order."""
        byp = self._by_problem(samples, ok)
        return {pid: Fraction(*byp[pid]) for pid in self._pids if pid in byp}

    @staticmethod
    def _paired(a: dict[str, Fraction], b: dict[str, Fraction]) -> tuple[float | None, list[Fraction]]:
        """Sign-flip test of a − b over the problems both configurations cover."""
        d = [a[pid] - b[pid] for pid in a if pid in b]
        return (paired_signflip_p(d) if d else None), d

    @staticmethod
    def _passk(samples: list[Sample], k: int, use_final: bool = False) -> float:
        """Average pass@k over problems (n = samples per problem)."""
        by_problem: dict[str, list[bool]] = defaultdict(list)
        for s in samples:
            by_problem[s.problem_id].append((s.final if use_final else s.initial).passed)
        if not by_problem:
            return 0.0
        return sum(pass_at_k(len(v), sum(v), min(k, len(v))) for v in by_problem.values()) / len(by_problem)

    def _ci(self, rates: list[Fraction]) -> tuple[float, float] | None:
        try:
            import numpy as np
        except ImportError:  # pragma: no cover - numpy is part of the [stats] extra
            return None
        if self._rng is None:
            self._rng = np.random.default_rng(PAPER_SEED)
        return cluster_bootstrap_ci([float(r) for r in rates], self._rng)

    def _vivado_ok(self, s: Sample) -> bool:
        """Pass under the Vivado criterion: strict pass, or a compile-stage failure that Vivado accepts and that is functionally correct."""
        return s.initial.passed or (self.rejudge is not None and s.sample_id in self.rejudge.vivado_pass)

    # ---- tables ------------------------------------------------------ #
    def table_passk(self) -> str:
        rows = ["| 模型 | 层级 | 题数 | n | pass@1/% | 95% CI（按题聚类自助法）/% | pass@5/% |", "|---|---|---|---|---|---|---|"]
        data = {}
        for m in self.models:
            for lv in Level:
                ss = self._baseline(m, lv)
                if not ss:
                    continue
                rates = list(self._rates(ss).values())
                p1, p5 = self._passk(ss, 1), self._passk(ss, 5)
                ci = self._ci(rates)
                ci_txt = f"[{100 * ci[0]:.0f}, {100 * ci[1]:.0f}]" if ci else "N/A（需要 numpy）"
                rows.append(f"| {m} | {lv.value} | {len(rates)} | {len(ss)} | {_pct(p1)} | {ci_txt} | {_pct(p5)} |")
                data[f"{m}/{lv.value}"] = {"n": len(ss), "problems": len(rates), "pass1": p1, "ci": list(ci) if ci else [p1, p1], "pass5": p5}
        self.data["passk"] = data
        return "\n".join(rows)

    def _level_tests(self, ok: Callable[[Sample], bool]) -> tuple[list[str], dict]:
        pairs = [(Level.L1, Level.L3), (Level.L2, Level.L3), (Level.L1, Level.L2)]
        rows = ["| 模型 | " + " | ".join(f"{a.value} vs {b.value}" for a, b in pairs) + " |", "|---|" + "---|" * len(pairs)]
        data = {}
        for m in self.models:
            r = {lv: [float(x) for x in self._rates(self._baseline(m, lv), ok).values()] for lv in Level}
            ps = [two_sample_permutation_p(r[a], r[b]) if r[a] and r[b] else None for a, b in pairs]
            rows.append(f"| {m} | " + " | ".join(_p(p) for p in ps) + " |")
            data[m] = {f"{a.value}-{b.value}": p for (a, b), p in zip(pairs, ps, strict=True)}
        return rows, data

    def _model_tests(self, ok: Callable[[Sample], bool]) -> tuple[list[str], dict]:
        rows = ["| 模型对 | 全部题目 | " + " | ".join(lv.value for lv in Level) + " |", "|---|---|" + "---|" * len(Level)]
        data = {}
        for a, b in combinations(self.models, 2):
            ps = [self._paired(self._rates(self._baseline(a, lv), ok), self._rates(self._baseline(b, lv), ok))[0] for lv in (None, *Level)]
            rows.append(f"| {a} vs {b} | " + " | ".join(_p(p) for p in ps) + " |")
            data[f"{a} vs {b}"] = dict(zip(["all", *(lv.value for lv in Level)], ps, strict=True))
        return rows, data

    def table_tests(self) -> str:
        lv_rows, lv_data = self._level_tests(_passed0)
        md_rows, md_data = self._model_tests(_passed0)
        self.data["tests"] = {"levels": lv_data, "models": md_data}
        return "\n".join(
            ["难度层级之间：两独立样本精确置换检验的 p 值（分析单位为题目）", "", *lv_rows, "", "模型之间：按题配对的符号翻转置换检验的 p 值", "", *md_rows]
        )

    def table_synth(self) -> str:
        rows = [
            "| 模型 | n | 编译失败/例 | 可综合率（严格判据）/% | 意外锁存器/例 | E9/例 | 仿真通过但综合失败/例 | 仿真失败且综合或实现报错/例 | Lint 告警密度 | 预筛与 Vivado 判定不一致/% |",
            "|---|---|---|---|---|---|---|---|---|---|",
        ]
        data = {}
        for m in self.models:
            ss = self._baseline(m)
            # Synthesizability uses *all* samples of the configuration as denominator (a sample that does
            # not compile is not synthesizable under the strict criterion); lint density and tool
            # disagreement are only defined for samples that reached synthesis.
            judged = [s for s in ss if s.initial.stage not in (Stage.INTERFACE, Stage.COMPILE)]
            if not judged:
                continue
            n_all = len(ss)
            n_compile = sum(s.initial.stage == Stage.COMPILE for s in ss)
            n_synth = sum(s.initial.synth_ok for s in judged)
            latch = sum(s.initial.unintended_latch for s in judged)
            e9 = sum(ErrorCode.E9_SIM_ONLY_CONSTRUCT in s.initial.errors for s in judged)
            sim_ok_synth_bad = sum(not s.initial.synth_ok for s in judged if s.initial.sim_passed)
            sim_bad_synth_err = sum(not s.initial.synth_ok and not s.initial.unintended_latch for s in judged if not s.initial.sim_passed)
            dens = [s.initial.lint_density for s in judged if s.initial.lint_density is not None]
            dens_txt = f"{sum(dens) / len(dens):.2f}" if dens else "N/A"
            dis = sum(s.initial.tool_disagreement for s in judged) / len(judged)
            rows.append(f"| {m} | {n_all} | {n_compile} | {_pct(n_synth / n_all)} | {latch} | {e9} | {sim_ok_synth_bad} | {sim_bad_synth_err} | {dens_txt} | {_pct(dis)} |")
            data[m] = {
                "n": n_all,
                "compile_failures": n_compile,
                "synth": n_synth / n_all,
                "latch": latch,
                "e9": e9,
                "sim_ok_synth_bad": sim_ok_synth_bad,
                "sim_bad_synth_error": sim_bad_synth_err,
                "lint_density": dens_txt,
                "disagreement": dis,
            }
        self.data["synth"] = data
        out = ["\n".join(rows)]
        if self.rejudge is not None:
            out.append(self._table_vivado_criterion())
        return "\n\n".join(out)

    def _table_vivado_criterion(self) -> str:
        rj = self.rejudge
        assert rj is not None
        rows = [
            "两级编译判据（Table 5）：严格判据下止于编译检查的样本另送 Vivado 综合与实现，无 Error 者再用 Vivado 仿真器运行正式测试台",
            "",
            "| 模型 | 严格判据编译失败/例 | 其中 Vivado 接受/例 | 其中功能亦正确/例 | 可综合率（严格→Vivado）/% | pass@1（严格→Vivado）/% |",
            "|---|---|---|---|---|---|",
        ]
        data = {}
        for m in self.models:
            ss = self._baseline(m)
            if not ss:
                continue
            n = len(ss)
            comp = [s for s in ss if s.initial.stage == Stage.COMPILE]
            v_ok = sum(s.sample_id in rj.vivado_ok for s in comp)
            v_pass = sum(s.sample_id in rj.vivado_pass for s in comp)
            synth = sum(s.initial.synth_ok for s in ss if s.initial.stage not in (Stage.INTERFACE, Stage.COMPILE))
            p_strict = sum(s.initial.passed for s in ss)
            rows.append(f"| {m} | {len(comp)} | {v_ok} | {v_pass} | {_pct(synth / n)} → {_pct((synth + v_ok) / n)} | {_pct(p_strict / n)} → {_pct((p_strict + v_pass) / n)} |")
            data[m] = {
                "compile_failures": len(comp),
                "vivado_ok": v_ok,
                "vivado_pass": v_pass,
                "synth_strict": synth / n,
                "synth_vivado": (synth + v_ok) / n,
                "pass1_strict": p_strict / n,
                "pass1_vivado": (p_strict + v_pass) / n,
            }
        lv_rows, lv_data = self._level_tests(self._vivado_ok)
        md_rows, md_data = self._model_tests(self._vivado_ok)
        by_level = ["| 模型 | " + " | ".join(f"{lv.value} pass@1（严格→Vivado）/%" for lv in Level) + " |", "|---|" + "---|" * len(Level)]
        for m in self.models:
            cells = []
            for lv in Level:
                ss = self._baseline(m, lv)
                if ss:
                    cells.append(f"{100 * sum(s.initial.passed for s in ss) / len(ss):.0f} → {100 * sum(self._vivado_ok(s) for s in ss) / len(ss):.0f}")
                else:
                    cells.append("—")
            by_level.append(f"| {m} | " + " | ".join(cells) + " |")
        self.data["vivado_criterion"] = {"models": data, "tests_levels": lv_data, "tests_models": md_data}
        return "\n".join(
            [*rows, "", *by_level, "", "Vivado 判据下难度层级之间的置换检验 p 值", "", *lv_rows, "", "Vivado 判据下模型之间的配对置换检验 p 值", "", *md_rows]
        )

    def table_errors(self) -> str:
        codes = list(ErrorCode)
        rows = ["| 层级 | 失败样本数 | " + " | ".join(f"{c.value} {c.label}" for c in codes) + " |", "|---|---|" + "---|" * len(codes)]
        data = {}
        for lv in Level:
            failed = [s for m in self.models for s in self._baseline(m, lv) if not s.initial.passed]
            if not failed:
                continue
            counts = {c: sum(s.initial.primary_error == c for s in failed) for c in codes}
            unclassified = sum(s.initial.primary_error is None for s in failed)
            n = len(failed)
            rows.append(f"| {lv.value} | {n} | " + " | ".join(f"{counts[c]}（{_pct(counts[c] / n)}%）" if counts[c] else "0" for c in codes) + " |")
            data[lv.value] = {c.value: counts[c] for c in codes} | {"unclassified": unclassified, "n": n}
        self.data["errors"] = data
        secondary = Counter(e.value for m in self.models for s in self._baseline(m) if not s.initial.passed for e in s.initial.errors if e != s.initial.primary_error)
        note = "次要标签（多标签，不计入首要错误）：" + ("；".join(f"{k} {v} 例" for k, v in sorted(secondary.items(), key=lambda kv: int(kv[0][1:]))) or "无")
        self.data["errors_secondary"] = dict(secondary)
        return "\n".join(rows) + "\n\n" + note

    def table_prompt_effects(self) -> str:
        specs = (SpecVersion.BRIEF, SpecVersion.DETAILED)
        main = ["| 模型 | 提示策略 | 简略规范 pass@1/% | 详细规范 pass@1/% | 差值/百分点 | 改善/变差/持平题数 | 配对检验 p | 编译失败全计为通过时的差值/百分点（p） |", "|---|---|---|---|---|---|---|---|"]
        strat = ["| 模型 | 规范版本 | 提示策略 | 相对零样本的差值/百分点 | 配对检验 p |", "|---|---|---|---|---|"]
        level = ["| 模型 | 层级 | 简略规范 pass@1/% | 详细规范 pass@1/% | 配对检验 p |", "|---|---|---|---|---|"]
        data: dict[str, dict] = {}

        def compiled_or_passed(s: Sample) -> bool:
            return s.initial.passed or s.initial.stage == Stage.COMPILE

        def mean(r: dict[str, Fraction]) -> float:
            return float(sum(r.values()) / len(r)) if r else 0.0

        for m in self.models:
            cfg = {(sp, st): self._config(m, sp, st) for sp in specs for st in Strategy}
            if not all(cfg[(sp, self.baseline[1])] for sp in specs):
                continue  # this model was only run with one specification version
            for st in Strategy:
                b, d = cfg[(SpecVersion.BRIEF, st)], cfg[(SpecVersion.DETAILED, st)]
                if not b or not d:
                    continue
                rb, rd = self._rates(b), self._rates(d)
                p, diffs = self._paired(rd, rb)
                ub, ud = self._rates(b, compiled_or_passed), self._rates(d, compiled_or_passed)
                p_u, _ = self._paired(ud, ub)
                trend = f"{sum(x > 0 for x in diffs)} / {sum(x < 0 for x in diffs)} / {sum(x == 0 for x in diffs)}"
                main.append(
                    f"| {m} | {st.value} | {_pct(mean(rb))} | {_pct(mean(rd))} | {100 * (mean(rd) - mean(rb)):+.1f} | {trend} | {_p(p)} | {100 * (mean(ud) - mean(ub)):+.1f}（{_p(p_u)}） |"
                )
                data[f"{m}/{st.value}"] = {"brief": mean(rb), "detailed": mean(rd), "p": p, "upper_bound_diff": mean(ud) - mean(ub), "upper_bound_p": p_u}
            for sp in (SpecVersion.DETAILED, SpecVersion.BRIEF):
                rz = self._rates(cfg[(sp, Strategy.ZERO_SHOT)])
                for st in Strategy:
                    if st == Strategy.ZERO_SHOT or not cfg[(sp, st)] or not rz:
                        continue
                    rs = self._rates(cfg[(sp, st)])
                    p, _ = self._paired(rs, rz)
                    strat.append(f"| {m} | {sp.value} | {st.value} | {100 * (mean(rs) - mean(rz)):+.1f} | {_p(p)} |")
                    data[f"{m}/{sp.value}/{st.value} vs zero"] = {"diff": mean(rs) - mean(rz), "p": p}
            for lv in Level:
                rb = self._rates(self._config(m, SpecVersion.BRIEF, self.baseline[1], lv))
                rd = self._rates(self._config(m, SpecVersion.DETAILED, self.baseline[1], lv))
                if rb and rd:
                    p, _ = self._paired(rd, rb)
                    level.append(f"| {m} | {lv.value} | {100 * mean(rb):.0f} | {100 * mean(rd):.0f} | {_p(p)} |")
                    data[f"{m}/{lv.value}/spec"] = {"brief": mean(rb), "detailed": mean(rd), "p": p}
        self.data["prompt"] = data
        if len(main) == 2:
            return "（没有同时运行简略与详细两版规范的模型）"
        return "\n".join([*main, "", "同一规范版本内各提示策略相对零样本", "", *strat, "", f"规范完整度的作用按层级（{self.baseline[1].value} 策略）", "", *level])

    def table_repair(self) -> str:
        rows = ["| 模型 | 范围 | n | 第0轮/% | 第1轮/% | 第2轮/% | 第3轮/% |", "|---|---|---|---|---|---|---|"]
        data: dict[str, dict] = {}
        for m in self.models:
            for label, lv in (("全体", None), ("L3", Level.L3)):
                ss = self._baseline(m, lv)
                if not ss:
                    continue
                curve = repair_curve([next((i for i, v in enumerate(s.rounds) if v.passed), -1) for s in ss], max_rounds=3)
                rows.append(f"| {m} | {label} | {len(ss)} | " + " | ".join(_pct(c) for c in curve) + " |")
                data.setdefault(m, {})["curve" if lv is None else "curve_L3"] = curve
        codes = list(ErrorCode)
        by_code = ["| 模型 | " + " | ".join(c.value for c in codes) + " |", "|---|" + "---|" * len(codes)]
        for label, ms in self._groups():
            failed = [s for m in ms for s in self._baseline(m) if not s.initial.passed]
            cells = []
            for c in codes:
                fs = [s for s in failed if s.initial.primary_error == c]
                k = sum(s.final.passed for s in fs)
                cells.append(f"{k}/{len(fs)}（{100 * k / len(fs):.0f}%）" if fs else "—")
                data.setdefault(label, {})[c.value] = [k, len(fs)]
            by_code.append(f"| {label} | " + " | ".join(cells) + " |")
        self.data["repair"] = data
        return "\n".join([*rows, "", "按首要错误类型的 3 轮修复成功数/失败样本数", "", *by_code])

    def table_resources(self) -> str:
        def med(v: list[float]) -> str:
            if not v:
                return "N/A"
            v = sorted(v)
            mid = len(v) // 2
            return f"{(v[mid] if len(v) % 2 else (v[mid - 1] + v[mid]) / 2):.2f}"

        def ratios(samples: list[Sample]) -> dict[str, list[float]]:
            out: dict[str, list[float]] = defaultdict(list)
            for s in samples:
                ref = self.bench.get(s.problem_id).reference_resources
                for key in ("LUT", "FF", "Fmax_MHz"):
                    if ref.get(key) and key in s.final.resources:
                        out[key].append(s.final.resources[key] / ref[key])
            return out

        rows = ["| 模型 | 层级 | 通过样本数 | LUT 比值（中位数） | FF 比值（中位数） | Fmax 比值（中位数） |", "|---|---|---|---|---|---|"]
        for label, ms in self._groups():
            for lv in Level:
                passed = [s for m in ms for s in self._baseline(m, lv) if s.final.passed and s.final.resources]
                if passed:
                    r = ratios(passed)
                    rows.append(f"| {label} | {lv.value} | {len(passed)} | {med(r['LUT'])} | {med(r['FF'])} | {med(r['Fmax_MHz'])} |")
        label, ms = self._groups()[0] if self.pool else ("全部模型", self.models)
        per = [f"L3 各题（{label}，含修复后通过者）", "", "| 题目 | 通过样本数 | LUT 比值中位数（范围） | FF 比值中位数 | Fmax 比值中位数 |", "|---|---|---|---|---|"]
        for pid in self._pids:
            if self._level[pid] != Level.L3:
                continue
            passed = [s for m in ms for s in self._baseline(m) if s.problem_id == pid and s.final.passed and s.final.resources]
            if passed:
                r = ratios(passed)
                rng = f"（{min(r['LUT']):.2f}～{max(r['LUT']):.2f}）" if r["LUT"] else ""
                per.append(f"| {pid} | {len(passed)} | {med(r['LUT'])}{rng} | {med(r['FF'])} | {med(r['Fmax_MHz'])} |")
        return "\n".join([*rows, "", *per])

    def table_problems(self) -> str:
        rows = ["| 层级 | 题目 | " + " | ".join(f"{m} 通过数/样本数" for m in self.models) + " |", "|---|---|" + "---|" * len(self.models)]
        byp = {m: self._by_problem(self._baseline(m)) for m in self.models}
        data = {}
        for pid in self._pids:
            cells = [f"{byp[m][pid][0]}/{byp[m][pid][1]}" if pid in byp[m] else "—" for m in self.models]
            rows.append(f"| {self._level[pid].value} | {pid} | " + " | ".join(cells) + " |")
            data[pid] = {m: list(byp[m][pid]) for m in self.models if pid in byp[m]}
        self.data["problems"] = data
        failed = [s for m in self.models for s in self._baseline(m) if not s.initial.passed and s.initial.primary_error]
        codes = [c for c in ErrorCode if any(s.initial.primary_error == c for s in failed)]
        err = ["| 层级 | 题目 | " + " | ".join(c.value for c in codes) + " |", "|---|---|" + "---|" * len(codes)]
        for pid in self._pids:
            cnt = Counter(s.initial.primary_error for s in failed if s.problem_id == pid)
            if cnt:
                err.append(f"| {self._level[pid].value} | {pid} | " + " | ".join(str(cnt.get(c, 0)) for c in codes) + " |")
        return "\n".join([*rows, "", "各题失败样本的首要错误（全部模型合并）", "", *err])

    def table_weak_tb(self) -> str:
        rj = self.rejudge
        assert rj is not None
        rows = ["| 范围 | 正式测试台判为功能错误/例 | 其中通过弱测试台/例 | 占比/% |", "|---|---|---|---|"]
        data = {}
        sim_failed = [s for m in self.models for s in self._baseline(m) if s.initial.stage == Stage.SIMULATION and s.sample_id in rj.weak]
        for label, sel in (
            ("L2 + L3", sim_failed),
            *((lv.value, [s for s in sim_failed if self._level[s.problem_id] == lv]) for lv in (Level.L2, Level.L3)),
            *((m, [s for s in sim_failed if s.model == m]) for m in self.models),
        ):
            if sel:
                k = sum(rj.weak[s.sample_id] for s in sel)
                rows.append(f"| {label} | {len(sel)} | {k} | {_pct(k / len(sel))} |")
                data[label] = [k, len(sel)]
        self.data["weak_tb"] = data
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
        self._rng = None  # the bootstrap sequence restarts with every build → identical intervals
        self.tables = {
            "T4_passk": self.table_passk(),
            "T4_tests": self.table_tests(),
            "T5_synth": self.table_synth(),
            "F4_errors": self.table_errors(),
            "T6_prompt": self.table_prompt_effects(),
            "F5_repair": self.table_repair(),
            "resources": self.table_resources(),
            "problems": self.table_problems(),
        }
        if self.rejudge is not None and self.rejudge.weak:
            self.tables["weak_tb"] = self.table_weak_tb()
        return self.tables

    def write(self, out_dir: Path, figures: bool = True) -> None:
        out_dir.mkdir(parents=True, exist_ok=True)
        if not self.tables:
            self.build()
        base = f"{self.baseline[0].value} × {self.baseline[1].value}"
        md = [f"# 评测结果汇总（样本数 {len(self.samples)}，模型 {', '.join(self.models)}）\n", f"除 T6_prompt 外均为主配置（{base}）；除 F5_repair 与 resources 外均为修复前（第 0 轮）。\n"]
        for name, table in self.tables.items():
            md.append(f"## {name}\n\n{table}\n")
        (out_dir / "tables.md").write_text("\n".join(md), encoding="utf-8", newline="\n")
        (out_dir / "summary.json").write_text(json.dumps(self.data, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8", newline="\n")
        if not figures:
            return
        try:
            from .figures import draw_all
        except ImportError:
            return  # matplotlib is optional
        try:
            draw_all(self, out_dir)
        except Exception as e:  # figures must never block the tables
            log.warning("figure generation failed: %s", e)
