"""Every number quoted in paper §4 (Tables 5–8, Figs. 3–6 and the surrounding text), computed
straight from a results database.

    python scripts/paper_stats.py [--db results/results.db] [--out data/report]

Writes ``<out>/paper_stats.txt`` (the full human-readable dump printed to stdout) and
``<out>/paper_data.json`` (the machine-readable input of ``scripts/make_paper_figures.py``).
Model codes follow the paper: A deepseek-v4-pro, B qwen3-coder-plus, C glm-5, D qwen3-coder-30b-a3b.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path
from statistics import mean, median

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from vleval.benchmark import Benchmark  # noqa: E402
from vleval.db import ResultStore  # noqa: E402
from vleval.models import ErrorCode, Level, SpecVersion, Stage, Strategy  # noqa: E402
from vleval.stats import fisher_exact, pass_at_k, wilson_ci  # noqa: E402

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--db", default=str(ROOT / "results" / "results.db"))
ap.add_argument("--out", default=str(ROOT / "data" / "report"))
args = ap.parse_args()
DB, OUT = Path(args.db), Path(args.out)
OUT.mkdir(parents=True, exist_ok=True)


class _Tee(io.TextIOBase):
    def __init__(self, *streams):
        self.streams = streams

    def write(self, s):
        for st in self.streams:
            st.write(s)
        return len(s)

    def flush(self):
        for st in self.streams:
            st.flush()


_txt = open(OUT / "paper_stats.txt", "w", encoding="utf-8", newline="\n")
sys.stdout = _Tee(sys.stdout, _txt)

bench = Benchmark(ROOT / "benchmark")
store = ResultStore(DB)
S = list(store.samples())
MODELS = ["Model A", "Model B", "Model C", "Model D"]
CLOUD = ["Model A", "Model B", "Model C"]
BASE = (SpecVersion.DETAILED, Strategy.ZERO_SHOT)
lvl = {p.id: p.level for p in bench}
title = {p.id: p.title for p in bench}


def pct(x: float, d: int = 1) -> str:
    return f"{100 * x:.{d}f}"


def ptxt(p: float) -> str:
    return f"{p:.3f}" if p >= 0.001 else f"{p:.1e}"


def base(m: str, lv: Level | None = None) -> list:
    return [s for s in S if s.model == m and (s.spec_version, s.strategy) == BASE and (lv is None or lvl[s.problem_id] == lv)]


def passk(ss: list, k: int) -> float:
    byp: dict[str, list[bool]] = defaultdict(list)
    for s in ss:
        byp[s.problem_id].append(s.initial.passed)
    return sum(pass_at_k(len(v), sum(v), min(k, len(v))) for v in byp.values()) / len(byp) if byp else 0.0


def fisher_sets(a: list, b: list) -> float:
    ka, kb = sum(s.initial.passed for s in a), sum(s.initial.passed for s in b)
    return fisher_exact(ka, len(a) - ka, kb, len(b) - kb)


print("=" * 78)
print("0. sample inventory / dates / versions")
for m in MODELS:
    ss = [s for s in S if s.model == m]
    dates = sorted({s.created_at[:10] for s in ss if s.created_at})
    print(f"  {m}: n={len(ss)} main={len(base(m))} version={sorted({s.model_version for s in ss})} dates={dates[:1]}..{dates[-1:]}")
trunc = sum(1 for s in S for v in s.rounds if "unexpected end of file" in v.tool_logs.get("compile", "") or "unexpected EOF" in v.tool_logs.get("compile", ""))
clog = sum(1 for s in S for v in s.rounds if "PLI call: '$clog2'" in v.tool_logs.get("compile", ""))
print(f"  truncated verdicts={trunc}  $clog2-rejected verdicts={clog}")

print("=" * 78)
print("T5. pass@1 [Wilson CI] / pass@5  (main config, pre-repair)")
for m in MODELS:
    row = []
    for lv in Level:
        ss = base(m, lv)
        k = sum(s.initial.passed for s in ss)
        lo, hi = wilson_ci(k, len(ss))
        row.append(f"{lv.value} {pct(k / len(ss))} [{pct(lo)}, {pct(hi)}] p@5 {pct(passk(ss, 5))} (n={len(ss)})")
    print(f"  {m}: " + " | ".join(row))

print("\n  pairwise Fisher (pre-repair pass@1) per level:")
for lv in Level:
    out = []
    for a, b in combinations(MODELS, 2):
        out.append(f"{a[-1]}-{b[-1]} p={ptxt(fisher_sets(base(a, lv), base(b, lv)))}")
    print(f"   {lv.value}: " + "; ".join(out))
print("  L1 vs L3 decline per model:")
for m in MODELS:
    print(f"   {m}: p={ptxt(fisher_sets(base(m, Level.L1), base(m, Level.L3)))}  L2 vs L3 p={ptxt(fisher_sets(base(m, Level.L2), base(m, Level.L3)))}")

print("\n  per-problem pass@1 (cloud models pooled, main config):")
for lv in Level:
    rows = []
    for p in bench.by_level(lv):
        ss = [s for m in CLOUD for s in base(m) if s.problem_id == p.id]
        k = sum(s.initial.passed for s in ss)
        per_model = "/".join(str(sum(s.initial.passed for s in base(m) if s.problem_id == p.id)) for m in MODELS)
        rows.append((k / len(ss) if ss else 0, p.id, title.get(p.id, ""), per_model))
    for r in sorted(rows, reverse=True):
        print(f"   {lv.value} {r[1]:18s} {r[2]:14s} cloud {pct(r[0], 0):>3}%  A/B/C/D passes of 10: {r[3]}")

print("=" * 78)
print("T6. synthesizability (main config, pre-repair; judged = reached simulation)")
for m in MODELS:
    ss = base(m)
    judged = [s for s in ss if s.initial.stage not in (Stage.INTERFACE, Stage.COMPILE)]
    n = len(judged)
    synth = sum(s.initial.synth_ok for s in judged)
    latch = sum(s.initial.unintended_latch for s in judged)
    e9 = sum(ErrorCode.E9_SIM_ONLY_CONSTRUCT in s.initial.errors for s in judged)
    sim_ok = [s for s in judged if s.initial.sim_passed]
    bad = [s for s in sim_ok if not s.initial.synth_ok]
    dens = [s.initial.lint_density for s in judged if s.initial.lint_density is not None]
    dis = sum(s.initial.tool_disagreement for s in judged)
    synth_err = [s for s in judged if not s.initial.synth_ok and not s.initial.unintended_latch]
    print(
        f"  {m}: judged={n}/{len(ss)} synth_ok={pct(synth / n)} latch={pct(latch / n)} ({latch}) e9={pct(e9 / n)} "
        f"sim_ok={len(sim_ok)} sim_ok&synth_bad={pct(len(bad) / len(sim_ok)) if sim_ok else 'NA'} ({len(bad)}) "
        f"lint_density mean={mean(dens):.2f} median={median(dens):.2f} disagreement={pct(dis / n)} ({dis}) synth_errors={len(synth_err)}"
    )
    lint_tot: Counter = Counter()
    for s in judged:
        lint_tot.update(s.initial.lint_counts)
    print(f"      lint categories: {lint_tot.most_common(8)}")
    if latch:
        print(f"      latch samples by problem: {Counter(s.problem_id for s in judged if s.initial.unintended_latch).most_common()}")
    if bad:
        print(f"      sim_ok&synth_bad by problem: {Counter(s.problem_id for s in bad).most_common()}")
    if synth_err:
        for s in synth_err[:3]:
            print(f"      synth error e.g. {s.problem_id}: {s.initial.tool_logs.get('synth', '')[:160]!r}")
# all-config disagreement (Model B)
allb = [s for s in S if s.model == "Model B" and s.initial.stage not in (Stage.INTERFACE, Stage.COMPILE)]
print(f"  Model B all configs: disagreement {pct(sum(s.initial.tool_disagreement for s in allb) / len(allb))} of {len(allb)} judged")

print("\n  stage of first failure per model (main config, pre-repair):")
for m in MODELS:
    print(f"  {m}: {dict(Counter(s.initial.stage.value for s in base(m)))}")

print("=" * 78)
print("T7. primary error distribution by level (4 models pooled, main config, pre-repair)")
for lv in Level:
    failed = [s for m in MODELS for s in base(m, lv) if not s.initial.passed]
    n = len(failed)
    cnt = Counter((s.initial.primary_error.value if s.initial.primary_error else "待复核") for s in failed)
    print(f"  {lv.value}: n={n} " + ", ".join(f"{k} {v} ({pct(v / n, 0)}%)" for k, v in sorted(cnt.items())))
    rev = [s for s in failed if s.initial.primary_error is None]
    if rev:
        print(f"      待复核 by problem: {Counter(s.problem_id for s in rev).most_common(6)}")
        print(f"      待复核 stage: {Counter(s.initial.stage.value for s in rev)}")
    multi = Counter(e.value for s in failed for e in s.initial.errors)
    print(f"      all labels (multi): {dict(sorted(multi.items()))}")
tot_fail = [s for m in MODELS for s in base(m) if not s.initial.passed]
auto = sum(1 for s in tot_fail if s.initial.primary_error is not None)
print(f"  total failed {len(tot_fail)}, auto-attributed {auto} ({pct(auto / len(tot_fail))}), review {len(tot_fail) - auto}")
print("  E2 breakdown (main config, round 0):")
for m in MODELS:
    e2 = [s for s in base(m) if s.initial.stage == Stage.COMPILE]
    log = lambda s: s.initial.tool_logs.get("compile", "")  # noqa: E731
    ansi = sum(1 for s in e2 if "Duplicate declaration" in log(s) or "Procedural assignment to wire" in log(s))
    sv = sum(1 for s in e2 if re.search(r"\b(logic|always_ff|always_comb|typedef|enum)\b", s.code or ""))
    print(f"   {m}: E2={len(e2)} ansi-reg={ansi} sv-constructs={sv}")
print("  E8 by problem (L3 failures, pooled):")
e8 = [s for m in MODELS for s in base(m, Level.L3) if s.initial.primary_error == ErrorCode.E8_PROTOCOL]
print(f"   {Counter(s.problem_id for s in e8).most_common()}")
print("  failed_cases tags (L3, pooled, round 0):")
tags: Counter = Counter()
for s in [s for m in MODELS for s in base(m, Level.L3) if s.initial.stage == Stage.SIMULATION]:
    for fc in s.initial.failed_cases:
        mm = re.search(r"tag=(\w+)", fc)
        tags[mm.group(1) if mm else "untagged"] += 1
print(f"   {tags.most_common()}")

print("=" * 78)
print("T8. Model B spec x strategy (all 30 problems, pre-repair)")
cfg: dict[tuple, list] = {}
for spec in SpecVersion:
    for st in Strategy:
        cfg[(spec, st)] = [s for s in S if s.model == "Model B" and s.spec_version == spec and s.strategy == st]
for st in Strategy:
    b, d = cfg[(SpecVersion.BRIEF, st)], cfg[(SpecVersion.DETAILED, st)]
    kb, kd = sum(s.initial.passed for s in b), sum(s.initial.passed for s in d)
    lob, hib = wilson_ci(kb, len(b))
    lod, hid = wilson_ci(kd, len(d))
    print(
        f"  {st.value:10s} brief {pct(kb / len(b))} [{pct(lob)}, {pct(hib)}] (n={len(b)})  detailed {pct(kd / len(d))} [{pct(lod)}, {pct(hid)}] (n={len(d)})  "
        f"diff {100 * (kd / len(d) - kb / len(b)):+.1f}  p={ptxt(fisher_sets(b, d))}"
    )
print("  strategy vs zero-shot within each spec:")
for spec in SpecVersion:
    z = cfg[(spec, Strategy.ZERO_SHOT)]
    out = []
    for st in Strategy:
        if st == Strategy.ZERO_SHOT:
            continue
        ss = cfg[(spec, st)]
        out.append(f"{st.value} {100 * (sum(s.initial.passed for s in ss) / len(ss) - sum(s.initial.passed for s in z) / len(z)):+.1f} p={ptxt(fisher_sets(z, ss))}")
    print(f"   {spec.value}: " + "; ".join(out))
print("  latch rate / E2 rate by config:")
for (spec, st), ss in cfg.items():
    judged = [s for s in ss if s.initial.stage not in (Stage.INTERFACE, Stage.COMPILE)]
    la = sum(s.initial.unintended_latch for s in judged)
    e2 = sum(s.initial.stage == Stage.COMPILE for s in ss)
    print(f"   {spec.value:8s}/{st.value:10s} latch {la}/{len(judged)} ({pct(la / len(judged))})  E2 {e2}/{len(ss)} ({pct(e2 / len(ss))})")
lz, lc = cfg[(SpecVersion.DETAILED, Strategy.ZERO_SHOT)], cfg[(SpecVersion.DETAILED, Strategy.CODING_CONSTRAINT)]
jz = [s for s in lz if s.initial.stage not in (Stage.INTERFACE, Stage.COMPILE)]
jc = [s for s in lc if s.initial.stage not in (Stage.INTERFACE, Stage.COMPILE)]
kz, kc = sum(s.initial.unintended_latch for s in jz), sum(s.initial.unintended_latch for s in jc)
print(f"  latch detailed zero vs constraint: {kz}/{len(jz)} vs {kc}/{len(jc)} p={ptxt(fisher_exact(kz, len(jz) - kz, kc, len(jc) - kc))}")
print("  per-level pass@1 by config (Model B):")
for (spec, st), ss in cfg.items():
    print(f"   {spec.value:8s}/{st.value:10s} " + " ".join(f"{lv.value} {pct(mean(s.initial.passed for s in ss if lvl[s.problem_id] == lv), 0)}" for lv in Level))

print("=" * 78)
print("T9. repair convergence (main config)")


def curve(ss: list) -> list[float]:
    r2p = [next((i for i, v in enumerate(s.rounds) if v.passed), -1) for s in ss]
    return [sum(1 for r in r2p if 0 <= r <= k) / len(ss) for k in range(4)]


for m in MODELS:
    print(f"  {m}: all " + " → ".join(pct(c) for c in curve(base(m))) + "   L3 " + " → ".join(pct(c) for c in curve(base(m, Level.L3))) + "   L1 " + " → ".join(pct(c) for c in curve(base(m, Level.L1))) + "   L2 " + " → ".join(pct(c) for c in curve(base(m, Level.L2))))
print("  repair success by primary error (cloud pooled / model D), main config:")
for name, ms in (("cloud", CLOUD), ("D", ["Model D"])):
    fs = [s for m in ms for s in base(m) if not s.initial.passed]
    grp = defaultdict(list)
    for s in fs:
        e = s.initial.primary_error
        key = "review" if e is None else ("E7" if e == ErrorCode.E7_FSM else ("E8" if e == ErrorCode.E8_PROTOCOL else ("E2" if e == ErrorCode.E2_LANGUAGE_SUBSET else "E1-6,9 local")))
        grp[key].append(s.final.passed)
    print(f"   {name}: " + "; ".join(f"{k} {sum(v)}/{len(v)} ({pct(sum(v) / len(v), 0)}%)" for k, v in sorted(grp.items())))
    per = defaultdict(list)
    for s in fs:
        per[s.initial.primary_error.value if s.initial.primary_error else "review"].append(s.final.passed)
    print("      per code: " + "; ".join(f"{k} {sum(v)}/{len(v)}" for k, v in sorted(per.items())))
print("  final (post-repair) pass by level, main config:")
for m in MODELS:
    print(f"   {m}: " + " ".join(f"{lv.value} {pct(mean(s.final.passed for s in base(m, lv)))}" for lv in Level) + f"  all {pct(mean(s.final.passed for s in base(m)))}")

print("=" * 78)
print("T10. resources vs Vivado golden reference (final passed samples, main config)")
for pid in ("sync_fifo", "uart", "spi_master", "spi_slave", "ps2_rx", "axi_lite_slave", "simple_dma", "i2c_master", "vga_timing", "rv32_datapath"):
    ref = bench.get(pid).reference_resources
    ss = [s for m in CLOUD for s in base(m) if s.problem_id == pid and s.final.passed and s.final.resources]
    r = {k: [s.final.resources[k] / ref[k] for s in ss if k in s.final.resources and ref.get(k)] for k in ("LUT", "FF", "Fmax_MHz")}
    med = {k: (f"{median(v):.2f}" if v else "NA") for k, v in r.items()}
    print(f"  {pid:15s} ref LUT/FF/Fmax = {ref.get('LUT')}/{ref.get('FF')}/{ref.get('Fmax_MHz', 0):.0f}  n={len(ss)}  median ratio LUT {med['LUT']} FF {med['FF']} Fmax {med['Fmax_MHz']}")
    if ss and r["LUT"]:
        print(f"                  LUT ratio range {min(r['LUT']):.2f}–{max(r['LUT']):.2f}; by model n: {Counter(s.model for s in ss)}")
print("  cloud pooled by level (median ratios):")
for lv in Level:
    rr = defaultdict(list)
    for m in CLOUD:
        for s in base(m, lv):
            if s.final.passed and s.final.resources:
                ref = bench.get(s.problem_id).reference_resources
                for k in ("LUT", "FF", "Fmax_MHz"):
                    if k in s.final.resources and ref.get(k):
                        rr[k].append(s.final.resources[k] / ref[k])
    print(f"   {lv.value}: " + " ".join(f"{k} {median(v):.2f} (n={len(v)})" for k, v in rr.items()))

print("=" * 78)
print("Case study candidates: Model B sync_fifo (main config) failing round 0, passing after repair")
for s in base("Model B"):
    if s.problem_id == "sync_fifo" and not s.initial.passed:
        r0 = s.initial
        print(f"  idx={s.index} stage0={r0.stage.value} errs={[e.value for e in r0.errors]} final_pass={s.final.passed} rounds={len(s.rounds)} final LUT/FF={s.final.resources.get('LUT')}/{s.final.resources.get('FF')}")
        for fc in r0.failed_cases[:3]:
            print(f"      {fc[:150]}")
print("  passing sync_fifo samples LUT (cloud, main):", sorted(int(s.final.resources.get("LUT", 0)) for m in CLOUD for s in base(m) if s.problem_id == "sync_fifo" and s.final.passed))

# ---- machine-readable export for the figure script -------------------------------------------
out = {
    "models": MODELS,
    "pass1": [[100 * mean(s.initial.passed for s in base(m, lv)) for lv in Level] for m in MODELS],
    "pass5": [[100 * passk(base(m, lv), 5) for lv in Level] for m in MODELS],
    "n_per_level": [[len(base(m, lv)) for lv in Level] for m in MODELS],
    "err_codes": [c.value for c in ErrorCode] + ["待复核"],
    "err_dist": [],
    "err_n": [],
    "strategies": [st.value for st in Strategy],
    "prompt_brief": [100 * mean(s.initial.passed for s in cfg[(SpecVersion.BRIEF, st)]) for st in Strategy],
    "prompt_detailed": [100 * mean(s.initial.passed for s in cfg[(SpecVersion.DETAILED, st)]) for st in Strategy],
    "prompt_n": [len(cfg[(SpecVersion.BRIEF, Strategy.ZERO_SHOT)]), len(cfg[(SpecVersion.DETAILED, Strategy.ZERO_SHOT)])],
    "repair_L3": {m: [100 * c for c in curve(base(m, Level.L3))] for m in MODELS},
    "repair_all": {m: [100 * c for c in curve(base(m))] for m in MODELS},
}
for lv in Level:
    failed = [s for m in MODELS for s in base(m, lv) if not s.initial.passed]
    n = len(failed)
    cnt = Counter((s.initial.primary_error.value if s.initial.primary_error else "待复核") for s in failed)
    out["err_dist"].append([100 * cnt.get(c, 0) / n if n else 0 for c in out["err_codes"]])
    out["err_n"].append(n)
dest = OUT / "paper_data.json"
dest.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
def _rel(p: Path) -> str:
    try:
        return p.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return p.name


print("wrote", _rel(dest), "and", _rel(OUT / "paper_stats.txt"))
sys.stdout = sys.__stdout__
_txt.close()
