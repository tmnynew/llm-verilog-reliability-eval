"""Single-sample judging pipeline (paper Fig. 2, §2.3 ③–⑤).

    interface check → Verilog-2001 compile/lint → functional simulation →
    synthesis (Yosys pre-screen, Vivado authoritative) → taxonomy

Each call runs in a fresh temporary directory so samples never interfere and
can be judged in parallel with :class:`concurrent.futures.ProcessPoolExecutor`.
"""

from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

from .extract import check_interface, effective_lines, sim_only_constructs, systemverilog_constructs
from .models import FUNCTIONAL_LINT_CATEGORIES, Problem, Stage, Verdict
from .stats import lint_density
from .taxonomy import Evidence, classify
from .tools import ToolConfig, Verilator, Vivado, Yosys, make_linter, make_simulator, which


class Judge:
    def __init__(self, cfg: ToolConfig, keep_workdirs: bool = False, workroot: Path | None = None):
        self.cfg = cfg
        self.sim = make_simulator(cfg)
        self.linter = make_linter(cfg)
        self.yosys = Yosys(cfg) if cfg.enable_yosys and which(cfg.yosys) else None
        self.vivado = Vivado(cfg) if cfg.enable_vivado and which(cfg.vivado) else None
        self.keep = keep_workdirs
        self.workroot = workroot

    # ------------------------------------------------------------------ #
    def judge(self, problem: Problem, code: str, seed: int = 1, coverage: bool = False, testbench: Path | None = None) -> Verdict:
        """Full pipeline. *testbench* overrides ``problem.testbench_path`` (e.g. the weak testbench)."""
        tb_path = testbench or problem.testbench_path
        ev = Evidence(interface_ok=True, problem_level=problem.level, problem_tags=problem.tags)
        logs = {}

        ok, issues = check_interface(code, problem.interface)
        ev.interface_ok, ev.interface_issues = ok, issues
        if not ok:
            return self._finish(ev, logs, failed=issues)

        work = Path(tempfile.mkdtemp(prefix=f"vleval_{problem.id}_", dir=self.workroot))
        try:
            dut = work / "dut.v"
            dut.write_text(code, encoding="utf-8")
            top = problem.interface.module

            # --- compile + lint ------------------------------------------ #
            lint = self.linter.lint(dut, top, work)
            logs["compile"] = lint.summary()
            ev.lint_counts = lint.data.get("lint", {})
            ev.sv_constructs = systemverilog_constructs(code)
            if not lint.ok:
                ev.compile_ok = False
                return self._finish(ev, logs, failed=[lint.summary(400)])

            # --- simulation ----------------------------------------------- #
            sim = self.sim.simulate(tb_path, dut, problem.tb_top, work, coverage=coverage, seed=seed)
            outcome = sim.data["outcome"]
            logs["sim"] = sim.summary()
            if sim.tool.endswith("-build"):
                # the simulator's front-end rejected the code although the linter accepted it:
                # still a Verilog-2001 compile failure (E2), not a functional one
                ev.compile_ok = False
                logs["compile"] = sim.summary()
                return self._finish(ev, logs, failed=[sim.summary(400)])
            ev.sim_ok = outcome.passed
            ev.failed_tags = outcome.tags
            failed_cases = outcome.fail_lines

            # --- synthesis ------------------------------------------------ #
            ev.sim_only_hits = sim_only_constructs(code)
            resources = {}
            disagreement = False
            ys = self.yosys.synth(dut, top, work) if self.yosys else None
            vv = self.vivado.synth_impl(dut, top, work, problem.clock_port) if self.vivado else None
            authority = vv or ys
            if authority is not None:
                logs["synth"] = "\n".join(authority.data.get("error_lines", [])) or authority.summary(600)
                ev.synth_ok = authority.ok
                ev.unintended_latch = authority.ok and authority.data.get("latch", 0) > 0
                resources = {k: authority.data[k] for k in ("LUT", "FF", "Fmax_MHz") if k in authority.data}
                if vv is not None and ys is not None:
                    disagreement = (vv.ok != ys.ok) or ((vv.data.get("latch", 0) > 0) != (ys.data.get("latch", 0) > 0))
            # A synthesis error that only involves sim-only constructs is E9 by
            # definition; when the code is otherwise fine the flag makes the
            # taxonomy explicit.
            verdict = self._finish(ev, logs, failed=failed_cases)
            verdict.lint_counts = ev.lint_counts
            functional = sum(v for k, v in ev.lint_counts.items() if k in FUNCTIONAL_LINT_CATEGORIES)
            verdict.lint_density = lint_density(functional, effective_lines(code)) if isinstance(self.linter, Verilator) else None
            verdict.resources = resources
            verdict.tool_disagreement = disagreement
            if coverage and "coverage" in sim.data:
                verdict.resources["coverage_pct"] = sim.data["coverage"]
            return verdict
        finally:
            if not self.keep:
                shutil.rmtree(work, ignore_errors=True)

    # ------------------------------------------------------------------ #
    def simulate_only(self, problem: Problem, code: str, testbench: Path | None = None, seed: int = 1) -> tuple[bool, bool, list[str]]:
        """Compile + simulate against *testbench* without lint/synthesis.

        Returns ``(compiled, sim_passed, fail_lines)``; used for mutation scoring of the weak
        testbench and for screening escape candidates, where synthesis would only cost time.
        """
        work = Path(tempfile.mkdtemp(prefix=f"vleval_{problem.id}_", dir=self.workroot))
        try:
            dut = work / "dut.v"
            dut.write_text(code, encoding="utf-8")
            sim = self.sim.simulate(testbench or problem.testbench_path, dut, problem.tb_top, work, seed=seed)
            if sim.tool.endswith("-build"):
                return False, False, [sim.summary(400)]
            outcome = sim.data["outcome"]
            return True, bool(outcome.passed), list(outcome.fail_lines)
        finally:
            if not self.keep:
                shutil.rmtree(work, ignore_errors=True)

    @staticmethod
    def _finish(ev: Evidence, logs: dict, failed) -> Verdict:
        cls = classify(ev)
        return Verdict(
            stage=cls.stage,
            passed=cls.stage == Stage.PASSED,
            sim_passed=ev.interface_ok and ev.compile_ok and ev.sim_ok,
            synth_ok=ev.synth_ok and not ev.unintended_latch,
            unintended_latch=ev.unintended_latch,
            errors=cls.errors,
            primary_error=cls.primary,
            failed_cases=list(failed),
            tool_logs=dict(logs, rationale="; ".join(cls.rationale), needs_review=str(cls.needs_review)),
        )
