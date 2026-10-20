"""Experiment 2 material: weak testbenches and escaped samples.

Each L2/L3 problem ships ``tb_weak.v`` – a deliberately incomplete testbench (basic
stimulus only, mutation score 56–85 %, mean ≈ 70 %) that students must strengthen to ≥ 90 %.  The
*escaped samples* are LLM-generated solutions that fail the full testbench ``tb.v`` but pass
``tb_weak.v``; students re-judge them with their improved testbench and report the detection
rate (paper §3.2).  This module scores the weak testbench and mines the escapes from the
released evaluation data.
"""

from __future__ import annotations

import json
import random
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path

from .extract import extract_code
from .models import Problem
from .mutation import MutationScore, mutation_score

# A weak testbench should kill roughly 40–85 % of the mutants.  The shipped set scores 56–85 %
# (mean ≈ 70 %): the survivors are timing-only / boundary mutants, every basic-function mutant is
# still caught, which is what "basic stimulus only" means.
WEAK_TARGET = (0.40, 0.85)


def weak_mutation_score(problem: Problem, run_sim: Callable[[Path], tuple[bool, bool]]) -> MutationScore:
    """Mutation score of ``tb_weak.v`` (same mutants and equivalent list as the full testbench)."""
    return mutation_score(problem, run_sim)


@dataclass
class EscapeCandidate:
    sample_id: int
    model: str
    spec_version: str
    strategy: str
    idx: int
    round: int
    code: str
    primary_error: str | None
    failed_cases: list[str]


def escape_candidates(samples: Iterable[dict], problem_id: str) -> list[EscapeCandidate]:
    """Code versions of *problem_id* that compiled but failed the full testbench.

    *samples* are records in the ``data/samples.jsonl`` format.  Two versions per sample are
    considered: the initial code (round 0, re-extracted from ``raw_response`` because ``code``
    holds the repaired version for samples that passed later) and, for samples that never passed,
    the final repaired code (``code``, attributed to the last round).  Per-round code stored by
    newer runs (``rounds[k].code``) is used for the intermediate rounds when present.  Duplicate
    code texts are dropped.
    """
    out: list[EscapeCandidate] = []
    seen: set[str] = set()

    def add(s: dict, k: int, r: dict, code: str) -> None:
        key = code.strip()
        if not key or key in seen:
            return
        seen.add(key)
        out.append(
            EscapeCandidate(
                sample_id=int(s["sample_id"]),
                model=s["model"],
                spec_version=s["spec_version"],
                strategy=s["strategy"],
                idx=int(s["idx"]),
                round=k,
                code=code,
                primary_error=r.get("primary_error"),
                failed_cases=list(r.get("failed_cases") or [])[:5],
            )
        )

    for s in samples:
        if s.get("problem_id") != problem_id or not s.get("rounds"):
            continue
        rounds = s["rounds"]
        if rounds[0].get("stage") == "simulation":
            add(s, 0, rounds[0], extract_code(s.get("raw_response") or "") or s.get("code") or "")
        if any(r.get("passed") for r in rounds):
            continue
        for k, r in enumerate(rounds[1:], 1):
            if r.get("stage") != "simulation":
                continue
            code = r.get("code") or (s.get("code") if k == len(rounds) - 1 else None) or ""
            add(s, k, r, code)
    return out


def select_escapes(
    candidates: list[EscapeCandidate],
    passes_weak: Callable[[str], bool],
    n: int = 10,
    seed: int = 1,
) -> tuple[list[EscapeCandidate], int]:
    """Pick up to *n* candidates that pass the weak testbench.

    Candidates are visited in a seeded random order, interleaving models so that the chosen set
    is not dominated by one model.  Returns ``(selected, n_tested)``.
    """
    rng = random.Random(seed)
    by_model: dict[str, list[EscapeCandidate]] = {}
    for c in candidates:
        by_model.setdefault(c.model, []).append(c)
    for lst in by_model.values():
        rng.shuffle(lst)
    order: list[EscapeCandidate] = []
    while any(by_model.values()):
        for m in sorted(by_model):
            if by_model[m]:
                order.append(by_model[m].pop())
    selected: list[EscapeCandidate] = []
    tested = 0
    for c in order:
        if len(selected) >= n:
            break
        tested += 1
        if passes_weak(c.code):
            selected.append(c)
    return selected, tested


def write_escapes(problem: Problem, selected: list[EscapeCandidate]) -> Path:
    d = problem.escapes_dir
    d.mkdir(parents=True, exist_ok=True)
    for old in d.glob("e*.v"):
        old.unlink()
    index = []
    for k, c in enumerate(selected, 1):
        name = f"e{k:02d}.v"
        (d / name).write_text(c.code if c.code.endswith("\n") else c.code + "\n", encoding="utf-8")
        index.append(
            {
                "file": name,
                "sample_id": c.sample_id,
                "model": c.model,
                "spec_version": c.spec_version,
                "strategy": c.strategy,
                "idx": c.idx,
                "round": c.round,
                "full_tb_primary_error": c.primary_error,
                "full_tb_failed_cases": c.failed_cases[:3],
            }
        )
    (d / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return d


def load_samples_jsonl(path: Path) -> Iterable[dict]:
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                yield json.loads(line)
