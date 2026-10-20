"""Command-line entry point: ``vleval <command> [options]``."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

from .benchmark import Benchmark, find_benchmark_root
from .models import Level, SpecVersion, Strategy
from .tools import ToolConfig


def _bench(args) -> Benchmark:
    return Benchmark(Path(args.benchmark) if args.benchmark else find_benchmark_root())


def _tools(args) -> ToolConfig:
    cfg = ToolConfig.from_yaml(Path(args.tools)) if args.tools and Path(args.tools).exists() else ToolConfig()
    if getattr(args, "vivado", False):
        cfg.enable_vivado = True
    return cfg


def _select_problems(bench: Benchmark, args) -> list:
    probs = list(bench)
    if getattr(args, "levels", None):
        wanted = {Level(x.strip()) for x in args.levels.split(",")}
        probs = [p for p in probs if p.level in wanted]
    if getattr(args, "problem", None):
        probs = [bench.get(pid.strip()) for pid in args.problem.split(",")]
    return probs


# --------------------------------------------------------------------------- #
def cmd_validate(args) -> int:
    bench = _bench(args)
    issues = bench.validate_static()
    for i in issues:
        print("STATIC:", i)
    print(f"{len(bench)} ready problems, {len(bench.planned())} planned, {len(issues)} static issue(s)")
    rc = 1 if issues else 0
    if args.sim:
        from .judge import Judge

        judge = Judge(_tools(args))
        for p in _select_problems(bench, args):
            v = judge.judge(p, p.golden_path.read_text(encoding="utf-8"))
            status = "PASS" if v.passed else f"FAIL@{v.stage.value} {v.failed_cases[:2]}"
            print(f"{p.id:24s} golden → {status}")
            rc |= 0 if v.passed else 1
    return rc


def cmd_mutate(args) -> int:
    from .mutation import generate_mutants, write_mutants

    bench = _bench(args)
    for p in _select_problems(bench, args):
        muts = generate_mutants(p.golden_path.read_text(encoding="utf-8"), n=args.n, seed=args.seed)
        d = write_mutants(p, muts)
        ops = {}
        for m in muts:
            ops[m.op] = ops.get(m.op, 0) + 1
        print(f"{p.id:24s} {len(muts):2d} mutants → {d}  {ops}")
    return 0


def cmd_mutation_score(args) -> int:
    from .judge import Judge
    from .mutation import mutation_score
    from .weak import WEAK_TARGET

    bench = _bench(args)
    judge = Judge(_tools(args))
    weak = args.tb == "weak"
    rc = 0
    print(f"testbench: {'tb_weak.v (Exp. 2 weak testbench)' if weak else 'tb.v'}")
    print("| problem | total | killed | survived | stillborn | equivalent | score |")
    print("|---|---|---|---|---|---|---|")
    for p in _select_problems(bench, args):
        if not (p.mutants_dir / "index.json").exists():
            print(f"| {p.id} | – | – | – | – | – | no mutants (run `vleval mutate`) |")
            continue
        if weak and not p.weak_testbench_path.exists():
            print(f"| {p.id} | – | – | – | – | – | no tb_weak.v |")
            continue
        tb = p.weak_testbench_path if weak else None
        if weak:  # the golden must pass the weak testbench, otherwise every mutant would be "killed"
            compiled, passed, lines = judge.simulate_only(p, p.golden_path.read_text(encoding="utf-8"), testbench=tb)
            if not (compiled and passed):
                print(f"| {p.id} | – | – | – | – | – | golden FAILS tb_weak.v: {(lines or ['no compile'])[0]} |")
                rc = 1
                continue

        def run_sim(path: Path, p=p, tb=tb):
            if weak:  # weak testbench: simulation only, no lint / synthesis needed
                compiled, passed, _ = judge.simulate_only(p, path.read_text(encoding="utf-8"), testbench=tb)
                return compiled, passed
            v = judge.judge(p, path.read_text(encoding="utf-8"))
            compiled = v.stage.value not in ("interface", "compile")
            # default: testbench-only kills (paper §2.2); --kill-on-synth also counts latch/synth failures
            return compiled, (v.passed if args.kill_on_synth else v.sim_passed)

        ms = mutation_score(p, run_sim)
        if weak:
            ok = WEAK_TARGET[0] <= ms.score <= WEAK_TARGET[1]
            flag = "" if ok else f"  ⚠ outside {100 * WEAK_TARGET[0]:.0f}–{100 * WEAK_TARGET[1]:.0f}% target"
        else:
            ok = ms.score >= args.threshold
            flag = "" if ok else "  ⚠ below threshold"
        print(
            f"| {p.id} | {ms.total} | {ms.killed} | {','.join(ms.survived) or '-'} | {','.join(ms.stillborn) or '-'} | {len(ms.equivalent)} | {100 * ms.score:.1f}%{flag} |"
        )
        rc |= 0 if ok else 1
    return rc


def cmd_escapes(args) -> int:
    """Mine Exp. 2 escaped samples: fail tb.v, pass tb_weak.v."""
    from .judge import Judge
    from .weak import escape_candidates, load_samples_jsonl, select_escapes, write_escapes

    bench = _bench(args)
    judge = Judge(_tools(args))
    samples = list(load_samples_jsonl(Path(args.data)))
    rc = 0
    print("| problem | candidates | tested | escapes | by model |")
    print("|---|---|---|---|---|")
    for p in _select_problems(bench, args):
        if not p.weak_testbench_path.exists():
            print(f"| {p.id} | – | – | – | no tb_weak.v |")
            continue
        cands = escape_candidates(samples, p.id)
        sel, tested = select_escapes(cands, lambda code, p=p: judge.simulate_only(p, code, testbench=p.weak_testbench_path)[1], n=args.n, seed=args.seed)
        if sel:
            write_escapes(p, sel)
        from collections import Counter

        bym = dict(Counter(c.model for c in sel))
        flag = "" if len(sel) >= args.n else f"  ⚠ only {len(sel)}"
        print(f"| {p.id} | {len(cands)} | {tested} | {len(sel)}{flag} | {bym} |")
        rc |= 0 if len(sel) >= args.n else 1
    return rc


def cmd_judge(args) -> int:
    from .judge import Judge

    bench = _bench(args)
    p = bench.get(args.problem)
    tb = Path(args.tb).resolve() if args.tb else None  # simulators run inside a temp work dir
    v = Judge(_tools(args), keep_workdirs=args.keep).judge(p, Path(args.file).read_text(encoding="utf-8"), testbench=tb)
    print(f"stage={v.stage.value} passed={v.passed} sim_passed={v.sim_passed} synth_ok={v.synth_ok} latch={v.unintended_latch}")
    print(f"errors={[e.value for e in v.errors]} primary={v.primary_error.value if v.primary_error else None}")
    print(f"lint={v.lint_counts} density={v.lint_density} resources={v.resources}")
    for line in v.failed_cases[:10]:
        print("  ", line)
    print("rationale:", v.tool_logs.get("rationale"))
    return 0 if v.passed else 1


def cmd_run(args) -> int:
    from .db import ResultStore
    from .judge import Judge
    from .llm import GoldenOracleClient, OpenAICompatClient, ResponseCache, load_model_configs
    from .prompting import PromptBuilder
    from .runner import Runner, RunPlan

    bench = _bench(args)
    probs = _select_problems(bench, args)
    specs = [SpecVersion(s) for s in args.specs.split(",")]
    strategies = [Strategy(s) for s in args.strategies.split(",")]
    store = ResultStore(Path(args.db))
    judge = Judge(_tools(args))
    prompts = PromptBuilder(Path(args.prompts) if args.prompts else None)

    if args.oracle:
        clients = [("golden-oracle", GoldenOracleClient(bench))]
    elif args.oracle_mutant:
        clients = [(f"mutant-oracle-{args.oracle_mutant}", GoldenOracleClient(bench, mutant_id=args.oracle_mutant))]
    else:
        cfgs = load_model_configs(Path(args.models))
        if args.model:
            cfgs = [c for c in cfgs if c.name in args.model.split(",")]
        cache = ResponseCache(Path(args.cache))
        clients = [(c.name, OpenAICompatClient(c, cache)) for c in cfgs]

    rc = 0
    for name, client in clients:
        plan = RunPlan(
            model_name=name,
            problems=probs,
            specs=specs,
            strategies=strategies,
            n_samples=args.n,
            temperature=args.temperature,
            max_repair_rounds=args.repair,
            workers=args.workers,
        )
        summary = Runner(client, judge, store, prompts).run(plan, resume=not args.no_resume)
        print(
            f"[{name}] total={summary.total} skipped={summary.skipped} pass_initial={summary.passed_initial} pass_final={summary.passed_final} errors={len(summary.errors)}"
        )
        rc |= 1 if summary.errors else 0
    return rc


def cmd_report(args) -> int:
    from .db import ResultStore
    from .report import Report

    bench = _bench(args)
    store = ResultStore(Path(args.db))
    rep = Report(store.samples(), bench)
    rep.build()
    rep.write(Path(args.out))
    k = rep.kappa(store.annotations())
    print((Path(args.out) / "tables.md").read_text(encoding="utf-8"))
    if k is not None:
        print(f"\nCohen's kappa (two raters): {k:.3f}")
    return 0


def cmd_export(args) -> int:
    from .export import export_dataset

    st = export_dataset(
        Path(args.db),
        Path(args.out),
        redact_paths=not args.no_redact,
        include_tool_logs=not args.no_tool_logs,
    )
    print(f"exported {st.samples} samples / {st.verdicts} verdicts → {args.out}")
    for name, size in sorted((st.files or {}).items()):
        print(f"  {name:16s} {size / 1e6:6.1f} MB")
    if st.residual_paths:
        print(f"WARNING: {st.residual_paths} local path(s) remain after redaction – inspect manifest.json")
    return 0


def cmd_annotate(args) -> int:
    from .db import ResultStore

    ResultStore(Path(args.db)).annotate(args.sample_id, args.rater, args.code, args.note or "")
    return 0


def cmd_reference(args) -> int:
    """Synthesise every golden model and store LUT/FF/Fmax in meta.json (reference_resources)."""
    import json

    from .judge import Judge

    bench = _bench(args)
    cfg = _tools(args)
    if not cfg.enable_vivado:
        print("warning: Vivado disabled – recording Yosys pre-screen estimates (no Fmax). Use --vivado for authoritative numbers.")
    judge = Judge(cfg)
    for p in _select_problems(bench, args):
        v = judge.judge(p, p.golden_path.read_text(encoding="utf-8"))
        if not v.passed:
            print(f"{p.id:24s} golden failed at {v.stage.value}; not recorded")
            continue
        meta_path = p.root / "meta.json"
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        meta["reference_resources"] = {k: v.resources[k] for k in ("LUT", "FF", "Fmax_MHz") if k in v.resources}
        meta["reference_tool"] = "vivado" if cfg.enable_vivado else "yosys"
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{p.id:24s} {meta['reference_resources']}")
    return 0


def cmd_web(args) -> int:
    from .web.app import serve

    serve(_bench(args), _tools(args), Path(args.db), host=args.host, port=args.port)
    return 0


# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="vleval", description="LLM-generated Verilog reliability evaluation platform")
    ap.add_argument("--benchmark", help="path to benchmark/ (default: auto-detect)")
    ap.add_argument("--tools", default=os.environ.get("VLEVAL_TOOLS", "configs/tools.yaml"), help="tool configuration YAML (default: $VLEVAL_TOOLS or configs/tools.yaml)")
    ap.add_argument("--vivado", action="store_true", help="enable Vivado as the authoritative synthesis judge")
    ap.add_argument("-v", "--verbose", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def sel(p):
        p.add_argument("--levels", help="comma list, e.g. L1,L2")
        p.add_argument("--problem", help="comma list of problem ids")

    p = sub.add_parser("validate", help="static checks (+ golden vs testbench with --sim)")
    p.add_argument("--sim", action="store_true")
    sel(p)
    p.set_defaults(fn=cmd_validate)

    p = sub.add_parser("mutate", help="generate mutants for golden models")
    p.add_argument("--n", type=int, default=20)
    p.add_argument("--seed", type=int, default=1)
    sel(p)
    p.set_defaults(fn=cmd_mutate)

    p = sub.add_parser("mutation-score", help="run testbench against mutants")
    p.add_argument("--threshold", type=float, default=0.95)
    p.add_argument("--tb", choices=["full", "weak"], default="full", help="tb.v (threshold ≥ 95 %%) or tb_weak.v (Exp. 2 baseline, target 40–85 %%)")
    p.add_argument("--kill-on-synth", action="store_true", help="also count synthesis-stage detection (unintended latch) as a kill")
    sel(p)
    p.set_defaults(fn=cmd_mutation_score)

    p = sub.add_parser("escapes", help="select Exp. 2 escaped samples (fail tb.v, pass tb_weak.v) from released data")
    p.add_argument("--data", default="data/samples.jsonl", help="samples.jsonl produced by `vleval export`")
    p.add_argument("--n", type=int, default=10, help="escapes per problem")
    p.add_argument("--seed", type=int, default=1)
    sel(p)
    p.set_defaults(fn=cmd_escapes)

    p = sub.add_parser("judge", help="judge one Verilog file against a problem")
    p.add_argument("problem")
    p.add_argument("file")
    p.add_argument("--tb", help="testbench to use instead of tb.v (e.g. tb_weak.v or a student's enhanced testbench)")
    p.add_argument("--keep", action="store_true", help="keep the work directory")
    p.set_defaults(fn=cmd_judge)

    p = sub.add_parser("run", help="generate + judge + repair for a set of configurations")
    p.add_argument("--models", default="configs/models.yaml")
    p.add_argument("--model", help="comma list of model names from the YAML")
    p.add_argument("--oracle", action="store_true", help="use the offline golden oracle instead of an LLM (self-test)")
    p.add_argument("--oracle-mutant", metavar="mXXX", help="offline oracle that returns mutant mXXX of each problem (exercises the failure/repair path)")
    p.add_argument("--specs", default="detailed", help="brief,detailed")
    p.add_argument("--strategies", default="zero", help="zero,few,constraint,cot")
    p.add_argument("--n", type=int, default=10)
    p.add_argument("--temperature", type=float, default=0.2)
    p.add_argument("--repair", type=int, default=3)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--db", default="results/results.db")
    p.add_argument("--cache", default="results/llm_cache.sqlite")
    p.add_argument("--prompts", help="override prompt template directory")
    p.add_argument("--no-resume", action="store_true")
    sel(p)
    p.set_defaults(fn=cmd_run)

    p = sub.add_parser("report", help="build tables/figures from a results DB")
    p.add_argument("--db", default="results/results.db")
    p.add_argument("--out", default="results/report")
    p.set_defaults(fn=cmd_report)

    p = sub.add_parser("export", help="export a results DB as a text dataset (JSONL + CSV, local paths redacted)")
    p.add_argument("--db", default="results/results.db")
    p.add_argument("--out", default="data", help="output directory")
    p.add_argument("--no-redact", action="store_true", help="keep local file-system paths in logs")
    p.add_argument("--no-tool-logs", action="store_true", help="skip tool_logs.jsonl (largest file)")
    p.set_defaults(fn=cmd_export)

    p = sub.add_parser("annotate", help="record a teacher's primary-error label")
    p.add_argument("--db", default="results/results.db")
    p.add_argument("sample_id", type=int)
    p.add_argument("rater")
    p.add_argument("code", help="E1..E9 or NONE")
    p.add_argument("--note")
    p.set_defaults(fn=cmd_annotate)

    p = sub.add_parser("reference", help="record golden LUT/FF/Fmax into meta.json (use --vivado for authoritative values)")
    sel(p)
    p.set_defaults(fn=cmd_reference)

    p = sub.add_parser("web", help="start the student-facing web UI")
    p.add_argument("--db", default="results/results.db")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8000)
    p.set_defaults(fn=cmd_web)
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    return int(args.fn(args))


if __name__ == "__main__":
    sys.exit(main())
