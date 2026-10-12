"""Core data model shared by every layer of the platform.

Design notes
------------
* Plain ``dataclasses`` – no ORM.  Persistence is handled by :mod:`vleval.db`
  which serialises these objects to SQLite / JSON.
* Every enum value that appears in the paper (error codes, stages, strategies)
  is defined here once so that the CLI, the judge and the report generator can
  never drift apart.
"""

from __future__ import annotations

import enum
import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any


# --------------------------------------------------------------------------- #
# Enumerations
# --------------------------------------------------------------------------- #
class Level(str, enum.Enum):
    L1 = "L1"  # combinational
    L2 = "L2"  # sequential
    L3 = "L3"  # system-level


class SpecVersion(str, enum.Enum):
    BRIEF = "brief"
    DETAILED = "detailed"


class Strategy(str, enum.Enum):
    ZERO_SHOT = "zero"
    FEW_SHOT = "few"
    CODING_CONSTRAINT = "constraint"
    CHAIN_OF_THOUGHT = "cot"


class Stage(str, enum.Enum):
    """Judging stages, in the order they are executed (paper Fig. 2)."""

    INTERFACE = "interface"
    COMPILE = "compile"
    SIMULATION = "simulation"
    SYNTHESIS = "synthesis"
    PASSED = "passed"


class ErrorCode(str, enum.Enum):
    """Nine-category taxonomy (paper Table 3)."""

    E1_INTERFACE = "E1"
    E2_LANGUAGE_SUBSET = "E2"
    E3_ASSIGNMENT_SEMANTICS = "E3"
    E4_RESET = "E4"
    E5_WIDTH = "E5"
    E6_LATCH = "E6"
    E7_FSM = "E7"
    E8_PROTOCOL = "E8"
    E9_SIM_ONLY_CONSTRUCT = "E9"

    @property
    def stage(self) -> Stage:
        return _ERROR_STAGE[self]

    @property
    def label(self) -> str:
        return _ERROR_LABEL[self]


_ERROR_STAGE = {
    ErrorCode.E1_INTERFACE: Stage.INTERFACE,
    ErrorCode.E2_LANGUAGE_SUBSET: Stage.COMPILE,
    ErrorCode.E3_ASSIGNMENT_SEMANTICS: Stage.SIMULATION,
    ErrorCode.E4_RESET: Stage.SIMULATION,
    ErrorCode.E5_WIDTH: Stage.SIMULATION,
    ErrorCode.E7_FSM: Stage.SIMULATION,
    ErrorCode.E8_PROTOCOL: Stage.SIMULATION,
    ErrorCode.E6_LATCH: Stage.SYNTHESIS,
    ErrorCode.E9_SIM_ONLY_CONSTRUCT: Stage.SYNTHESIS,
}
_ERROR_LABEL = {
    ErrorCode.E1_INTERFACE: "接口错误",
    ErrorCode.E2_LANGUAGE_SUBSET: "语言子集兼容性",
    ErrorCode.E3_ASSIGNMENT_SEMANTICS: "赋值语义错误",
    ErrorCode.E4_RESET: "复位错误",
    ErrorCode.E5_WIDTH: "位宽与截断",
    ErrorCode.E6_LATCH: "意外锁存器",
    ErrorCode.E7_FSM: "状态机错误",
    ErrorCode.E8_PROTOCOL: "协议错误",
    ErrorCode.E9_SIM_ONLY_CONSTRUCT: "仿真专用结构",
}

#: Lint categories that count as *functionally relevant* (paper Table 1).
FUNCTIONAL_LINT_CATEGORIES = frozenset({"WIDTH", "LATCH", "MULTIDRIVEN", "BLKSEQ", "COMBDLY", "CASEINCOMPLETE", "UNOPTFLAT"})


# --------------------------------------------------------------------------- #
# Benchmark model
# --------------------------------------------------------------------------- #
@dataclass(frozen=True)
class Port:
    name: str
    direction: str  # "input" | "output"
    width: int = 1

    def __post_init__(self) -> None:
        if self.direction not in ("input", "output"):
            raise ValueError(f"port {self.name}: direction must be input/output")
        if self.width < 1:
            raise ValueError(f"port {self.name}: width must be >= 1")


@dataclass(frozen=True)
class Interface:
    module: str
    ports: list[Port]
    parameters: dict[str, int] = field(default_factory=dict)

    def port_map(self) -> dict[str, Port]:
        return {p.name: p for p in self.ports}

    def to_verilog_header(self) -> str:
        """Render the exact header students/LLMs must reproduce."""
        lines = [f"module {self.module}"]
        if self.parameters:
            params = ", ".join(f"parameter {k} = {v}" for k, v in self.parameters.items())
            lines[0] += f" #({params})"
        lines[0] += " ("
        body = []
        for p in self.ports:
            rng = f" [{p.width - 1}:0]" if p.width > 1 else ""
            body.append(f"    {p.direction}{rng} {p.name}")
        lines.append(",\n".join(body))
        lines.append(");")
        return "\n".join(lines)


@dataclass
class Problem:
    """One benchmark problem = one directory under ``benchmark/<level>/<id>``."""

    id: str
    level: Level
    title: str
    interface: Interface
    root: Path
    tags: list[str] = field(default_factory=list)
    testbench_type: str = "exhaustive"  # exhaustive | cycle | transaction
    allowed_latency: int = 0  # extra cycles tolerated by cycle-level comparison
    reference_resources: dict[str, float] = field(default_factory=dict)  # LUT/FF/Fmax of golden
    clock_port: str | None = None
    status: str = "ready"  # ready | planned

    # ----- file accessors ------------------------------------------------ #
    @property
    def golden_path(self) -> Path:
        return self.root / "golden.v"

    @property
    def testbench_path(self) -> Path:
        return self.root / "tb.v"

    @property
    def weak_testbench_path(self) -> Path:
        """Deliberately incomplete testbench (mutation score ≈ 60 %) handed to students in Exp. 2."""
        return self.root / "tb_weak.v"

    @property
    def escapes_dir(self) -> Path:
        """LLM samples that fail tb.v but pass tb_weak.v (Exp. 2 teaching material)."""
        return self.root / "escapes"

    @property
    def mutants_dir(self) -> Path:
        return self.root / "mutants"

    def spec(self, version: SpecVersion) -> str:
        return (self.root / f"spec_{version.value}.md").read_text(encoding="utf-8")

    @property
    def tb_top(self) -> str:
        return f"tb_{self.interface.module}"


# --------------------------------------------------------------------------- #
# Evaluation model
# --------------------------------------------------------------------------- #
@dataclass
class ToolResult:
    """Uniform wrapper around any external tool invocation."""

    tool: str
    ok: bool
    returncode: int
    stdout: str = ""
    stderr: str = ""
    duration_s: float = 0.0
    timed_out: bool = False
    data: dict[str, Any] = field(default_factory=dict)  # parsed, tool-specific payload

    def summary(self, limit: int = 1500) -> str:
        text = (self.stderr or self.stdout or "").strip()
        return text[-limit:]


@dataclass
class Verdict:
    """Result of judging one piece of generated code (one sample, one round)."""

    stage: Stage
    passed: bool
    sim_passed: bool = False
    synth_ok: bool = False
    unintended_latch: bool = False
    errors: list[ErrorCode] = field(default_factory=list)  # all detected (multi-label)
    primary_error: ErrorCode | None = None  # first by stage order (paper §2.4)
    lint_density: float | None = None  # functional warnings per 100 effective lines
    lint_counts: dict[str, int] = field(default_factory=dict)
    failed_cases: list[str] = field(default_factory=list)  # testbench TB_FAIL lines
    resources: dict[str, float] = field(default_factory=dict)  # LUT, FF, Fmax_MHz
    tool_disagreement: bool = False  # Yosys pre-screen vs Vivado differ
    tool_logs: dict[str, str] = field(default_factory=dict)
    # Code judged in this round and the model reply it was extracted from (round 0 = initial
    # generation, round k = k-th repair).  Lets students diff successive repair rounds (Exp. 4).
    # None for records written before this field existed (the 2026-10 paper data).
    code: str | None = None
    raw_response: str | None = None

    def feedback_for_repair(self) -> str:
        """Human-readable error digest fed back to the LLM (paper §2.3 step 6)."""
        parts: list[str] = []
        if self.stage == Stage.INTERFACE:
            parts.append("接口检查失败：" + "; ".join(self.failed_cases))
        elif self.stage == Stage.COMPILE:
            parts.append("编译失败（仅允许 Verilog-2001）：\n" + self.tool_logs.get("compile", ""))
        elif self.stage == Stage.SIMULATION:
            parts.append("功能仿真未通过，失败用例：\n" + "\n".join(self.failed_cases[:10]))
        elif self.stage == Stage.SYNTHESIS:
            if self.unintended_latch:
                parts.append("综合推断出规范未要求的锁存器（检查组合 always 块的分支完整性/default）。")
            parts.append("综合日志摘要：\n" + self.tool_logs.get("synth", ""))
        return "\n".join(parts)


@dataclass
class Sample:
    """One generated code sample with its judging history."""

    problem_id: str
    model: str
    spec_version: SpecVersion
    strategy: Strategy
    index: int
    prompt: str
    raw_response: str
    code: str
    rounds: list[Verdict] = field(default_factory=list)
    model_version: str = ""
    created_at: str = ""
    temperature: float = 0.2

    @property
    def initial(self) -> Verdict:
        return self.rounds[0]

    @property
    def final(self) -> Verdict:
        return self.rounds[-1]

    @property
    def repair_rounds(self) -> int:
        return len(self.rounds) - 1

    def to_json(self) -> str:
        def default(o: Any) -> Any:
            if isinstance(o, enum.Enum):
                return o.value
            if isinstance(o, Path):
                return str(o)
            raise TypeError(type(o))

        return json.dumps(asdict(self), ensure_ascii=False, default=default)
