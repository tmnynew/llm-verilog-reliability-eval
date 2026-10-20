"""Experiment runner: generate → judge → repair loop → persist (paper §2.3 ①–⑥)."""

from __future__ import annotations

import itertools
import logging
import time
from collections.abc import Iterable, Sequence
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field

from .db import ResultStore
from .extract import extract_code
from .judge import Judge
from .llm import ChatClient
from .models import Problem, Sample, SpecVersion, Strategy
from .prompting import PromptBuilder, flatten

log = logging.getLogger("vleval.runner")


@dataclass
class RunPlan:
    model_name: str
    problems: Sequence[Problem]
    specs: Sequence[SpecVersion] = (SpecVersion.DETAILED,)
    strategies: Sequence[Strategy] = (Strategy.ZERO_SHOT,)
    n_samples: int = 10  # paper: n = 10 per configuration
    temperature: float = 0.2
    max_repair_rounds: int = 3
    seed_base: int = 20240901
    workers: int = 4

    def configurations(self) -> Iterable[tuple]:
        return itertools.product(self.problems, self.specs, self.strategies, range(self.n_samples))


@dataclass
class RunSummary:
    total: int = 0
    skipped: int = 0
    passed_initial: int = 0
    passed_final: int = 0
    errors: list[str] = field(default_factory=list)


class Runner:
    def __init__(self, client: ChatClient, judge: Judge, store: ResultStore, prompts: PromptBuilder | None = None, model_version: str = ""):
        self.client = client
        self.judge = judge
        self.store = store
        self.prompts = prompts or PromptBuilder()
        self.model_version = model_version

    # ------------------------------------------------------------------ #
    def run_one(self, plan: RunPlan, problem: Problem, spec: SpecVersion, strategy: Strategy, index: int) -> Sample:
        messages = self.prompts.build(problem, spec, strategy)
        comp = self.client.complete(messages, temperature=plan.temperature, seed_index=plan.seed_base + index)
        code = extract_code(comp.text)
        sample = Sample(
            problem_id=problem.id,
            model=plan.model_name,
            spec_version=spec,
            strategy=strategy,
            index=index,
            prompt=flatten(messages),
            raw_response=comp.text,
            code=code,
            model_version=comp.model_version or self.model_version,
            created_at=time.strftime("%Y-%m-%dT%H:%M:%S"),
            temperature=plan.temperature,
        )
        verdict = self.judge.judge(problem, code, seed=plan.seed_base + index)
        verdict.code, verdict.raw_response = code, comp.text
        sample.rounds.append(verdict)

        # --- repair loop (⑥) ------------------------------------------- #
        history = list(messages) + [{"role": "assistant", "content": comp.text}]
        for _round in range(plan.max_repair_rounds):
            if verdict.passed:
                break
            history.append(self.prompts.build_repair(problem, code, verdict.feedback_for_repair()))
            comp = self.client.complete(history, temperature=plan.temperature, seed_index=plan.seed_base + index + 1000 * (_round + 1))
            history.append({"role": "assistant", "content": comp.text})
            code = extract_code(comp.text)
            verdict = self.judge.judge(problem, code, seed=plan.seed_base + index)
            verdict.code, verdict.raw_response = code, comp.text  # per-round code kept for diffing
            sample.rounds.append(verdict)
        sample.code = code if verdict.passed else sample.code  # keep the initial code as the sample's code unless repaired successfully
        return sample

    def run(self, plan: RunPlan, resume: bool = True) -> RunSummary:
        summary = RunSummary()
        jobs = []
        with ThreadPoolExecutor(max_workers=plan.workers) as pool:
            for problem, spec, strategy, idx in plan.configurations():
                summary.total += 1
                if resume and self.store.exists(plan.model_name, problem.id, spec, strategy, idx):
                    summary.skipped += 1
                    continue
                jobs.append(pool.submit(self.run_one, plan, problem, spec, strategy, idx))
            for fut in as_completed(jobs):
                try:
                    sample = fut.result()
                except Exception as e:  # never abort a whole run for one sample
                    log.exception("sample failed")
                    summary.errors.append(str(e))
                    continue
                self.store.add(sample)
                summary.passed_initial += sample.initial.passed
                summary.passed_final += sample.final.passed
                log.info(
                    "%s %s %s/%s #%d initial=%s final=%s",
                    sample.model,
                    sample.problem_id,
                    sample.spec_version.value,
                    sample.strategy.value,
                    sample.index,
                    sample.initial.stage.value,
                    sample.final.stage.value,
                )
        return summary
