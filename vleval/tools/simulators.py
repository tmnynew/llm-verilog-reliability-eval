"""Verilator 5 and Icarus Verilog wrappers (compile / lint / simulate / coverage)."""

from __future__ import annotations

import re
from pathlib import Path

from ..models import ToolResult
from .base import ToolConfig, run
from .tbproto import TbOutcome, parse_tb_output

_WARN_RE = re.compile(r"^%Warning-([A-Z0-9_]+):", re.M)
_ERR_RE = re.compile(r"^%Error", re.M)
_COV_RE = re.compile(r"Total coverage \(([\d.]+)/([\d.]+)\)\s*([\d.]+)%")

# Language level for the compile check.  IEEE 1364-2005 is a strict superset of
# Verilog-2001 (adds `$clog2`, `uwire`, `localparam` in port lists ...) and is
# still *not* SystemVerilog, so SV-only constructs (logic/always_ff/...) remain
# compile errors (E2) while `$clog2` -- which Vivado, Yosys and Icarus all
# accept -- is not spuriously rejected.
VERILOG_2001 = ["--default-language", "1364-2005"]
IVERILOG_GEN = "-g2005"


def normalize_lint_category(cat: str) -> str:
    """Verilator ≥ 5.0 splits WIDTH into WIDTHEXPAND / WIDTHTRUNC / WIDTHCONCAT / WIDTHXZEXPAND;
    the paper's metric counts them as one category."""
    return "WIDTH" if cat.startswith("WIDTH") else cat


class Verilator:
    def __init__(self, cfg: ToolConfig):
        self.cfg = cfg

    # ---- compile + lint in one pass ---------------------------------- #
    def lint(self, dut: Path, top: str, workdir: Path) -> ToolResult:
        """Verilog-2001/2005 (IEEE 1364-2005) compile check with full lint.

        ``ok`` is False when Verilator reports ``%Error`` (syntax / SV
        constructs → E2).  Warnings are parsed into ``data['lint']``.
        """
        cmd = [self.cfg.verilator, "--lint-only", "-Wall", "-Wno-fatal", "-Wno-DECLFILENAME", "-Wno-UNUSED", *VERILOG_2001, str(dut), "--top-module", top]
        res = run(cmd, workdir, self.cfg.compile_timeout_s, "verilator-lint")
        text = res.stderr + res.stdout
        counts: dict[str, int] = {}
        for cat in _WARN_RE.findall(text):
            cat = normalize_lint_category(cat)
            counts[cat] = counts.get(cat, 0) + 1
        res.data["lint"] = counts
        res.ok = res.returncode == 0 and not _ERR_RE.search(text)
        return res

    # ---- simulation ---------------------------------------------------- #
    def simulate(self, tb: Path, dut: Path, tb_top: str, workdir: Path, coverage: bool = False, seed: int = 1) -> ToolResult:
        obj = workdir / "obj_dir"
        cmd = [
            self.cfg.verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "-Wno-lint",
            "-Wno-style",
            "-Wno-MULTIDRIVEN",
            *VERILOG_2001,
            "--Mdir",
            str(obj),
            "-o",
            "sim",
            str(tb),
            str(dut),
            "--top-module",
            tb_top,
            "+define+SEED=" + str(seed),
        ]
        if coverage:
            cmd.insert(1, "--coverage")
        build = run(cmd, workdir, self.cfg.compile_timeout_s, "verilator-build")
        if not build.ok:
            build.data["outcome"] = TbOutcome(False, tags=["crash"], crashed=True, fail_lines=[build.summary(400)])
            return build
        exe = obj / ("sim.exe" if (obj / "sim.exe").exists() else "sim")
        sim = run([str(exe), f"+verilator+seed+{seed}"], workdir, self.cfg.sim_timeout_s, "verilator-sim")
        outcome = parse_tb_output(sim.stdout, sim.timed_out)
        sim.ok = outcome.passed
        sim.data["outcome"] = outcome
        if coverage and (workdir / "coverage.dat").exists():
            sim.data["coverage"] = self._coverage(workdir)
        return sim

    def _coverage(self, workdir: Path) -> float | None:
        res = run([self.cfg.verilator_coverage, "coverage.dat"], workdir, 60, "verilator-coverage")
        m = _COV_RE.search(res.stdout + res.stderr)
        return float(m.group(3)) if m else None


class Icarus:
    """Fallback simulator (no lint support → lint density is reported as N/A)."""

    def __init__(self, cfg: ToolConfig):
        self.cfg = cfg

    def lint(self, dut: Path, top: str, workdir: Path) -> ToolResult:
        res = run([self.cfg.iverilog, IVERILOG_GEN, "-tnull", "-s", top, str(dut)], workdir, self.cfg.compile_timeout_s, "iverilog-compile")
        res.data["lint"] = {}
        return res

    def simulate(self, tb: Path, dut: Path, tb_top: str, workdir: Path, coverage: bool = False, seed: int = 1) -> ToolResult:
        vvp = workdir / "sim.vvp"
        build = run(
            [self.cfg.iverilog, IVERILOG_GEN, f"-DSEED={seed}", "-o", str(vvp), "-s", tb_top, str(tb), str(dut)],
            workdir,
            self.cfg.compile_timeout_s,
            "iverilog-build",
        )
        if not build.ok:
            build.data["outcome"] = TbOutcome(False, tags=["crash"], crashed=True, fail_lines=[build.summary(400)])
            return build
        sim = run([self.cfg.vvp, "-n", str(vvp)], workdir, self.cfg.sim_timeout_s, "iverilog-sim")
        outcome = parse_tb_output(sim.stdout, sim.timed_out)
        sim.ok = outcome.passed
        sim.data["outcome"] = outcome
        return sim


def make_simulator(cfg: ToolConfig):
    name = cfg.pick_simulator()
    return Verilator(cfg) if name == "verilator" else Icarus(cfg)


def make_linter(cfg: ToolConfig):
    """Verilator lint is preferred even when Icarus does the simulation (e.g. no C++ toolchain)."""
    name = cfg.pick_linter()
    return Verilator(cfg) if name == "verilator" else Icarus(cfg)
