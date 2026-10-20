"""Error taxonomy rules (paper Table 3 and §2.4).

The classifier is deliberately *evidence based*: every code it emits is tied
to an observable produced by a tool or by the testbench.  When the evidence
is insufficient the sample is flagged ``needs_review`` and the primary error
is left ``None`` so that a teacher makes the final call (two-rater Kappa is
computed on those decisions, see :mod:`vleval.stats`).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .models import ErrorCode, Level, Stage

#: Testbench failure tags (``TB_FAIL tag=<tag> ...``) → error code.
TB_TAG_TO_CODE: dict[str, ErrorCode] = {
    "reset": ErrorCode.E4_RESET,
    "width": ErrorCode.E5_WIDTH,
    "state": ErrorCode.E7_FSM,
    "timing": ErrorCode.E7_FSM,  # output outside the allowed latency window
    "proto": ErrorCode.E8_PROTOCOL,
    "handshake": ErrorCode.E8_PROTOCOL,
}

#: Order used to pick the primary error inside the simulation stage
#: ("事务级断言定位的类别优先").
_SIM_PRIORITY = [
    ErrorCode.E8_PROTOCOL,
    ErrorCode.E4_RESET,
    ErrorCode.E7_FSM,
    ErrorCode.E3_ASSIGNMENT_SEMANTICS,
    ErrorCode.E5_WIDTH,
    ErrorCode.E6_LATCH,  # incomplete case/if that holds a stale value also breaks simulation
]


@dataclass
class Evidence:
    """Everything the judge collected for one sample."""

    interface_ok: bool
    interface_issues: list[str] = field(default_factory=list)
    compile_ok: bool = True
    compile_log: str = ""
    sv_constructs: dict[str, int] = field(default_factory=dict)
    sim_ok: bool = True
    failed_tags: list[str] = field(default_factory=list)  # tags parsed from TB_FAIL lines
    lint_counts: dict[str, int] = field(default_factory=dict)  # Verilator category → count
    synth_ok: bool = True
    synth_error_log: str = ""
    unintended_latch: bool = False
    sim_only_hits: dict[str, int] = field(default_factory=dict)
    post_synth_mismatch: bool = False  # RTL sim passed but gate-level sim failed
    problem_level: Level = Level.L1
    problem_tags: list[str] = field(default_factory=list)


@dataclass
class Classification:
    stage: Stage
    errors: list[ErrorCode]
    primary: ErrorCode | None
    needs_review: bool
    rationale: list[str] = field(default_factory=list)


def classify(ev: Evidence) -> Classification:
    errors: list[ErrorCode] = []
    why: list[str] = []

    # ---- stage 1: interface --------------------------------------------- #
    if not ev.interface_ok:
        why.append("interface check failed: " + "; ".join(ev.interface_issues[:3]))
        return Classification(Stage.INTERFACE, [ErrorCode.E1_INTERFACE], ErrorCode.E1_INTERFACE, False, why)

    # ---- stage 2: compile ----------------------------------------------- #
    if not ev.compile_ok:
        if ev.sv_constructs:
            why.append(f"SystemVerilog-only constructs: {ev.sv_constructs}")
        else:
            why.append("Verilog-2001 compile error")
        return Classification(Stage.COMPILE, [ErrorCode.E2_LANGUAGE_SUBSET], ErrorCode.E2_LANGUAGE_SUBSET, False, why)

    # ---- stage 3: simulation ------------------------------------------- #
    if not ev.sim_ok:
        for tag in ev.failed_tags:
            code = TB_TAG_TO_CODE.get(tag)
            if code and code not in errors:
                errors.append(code)
                why.append(f"testbench tag {tag!r} → {code.value}")
        if ev.lint_counts.get("BLKSEQ", 0) or ev.lint_counts.get("COMBDLY", 0):
            errors.append(ErrorCode.E3_ASSIGNMENT_SEMANTICS)
            why.append("lint BLKSEQ/COMBDLY with failing simulation")
        if ev.lint_counts.get("WIDTH", 0):
            errors.append(ErrorCode.E5_WIDTH)
            why.append("lint WIDTH with failing simulation")
        # Untagged functional failure on FSM / system-level problems: the cycle-level or
        # transaction-level *comparison* failed, which Table 3 assigns to E7.  E8 is only
        # emitted for protocol *assertions* (proto/handshake tags above); L1 exhaustive
        # mismatches without further evidence stay unclassified (needs_review).
        if not errors:
            if "fsm" in ev.problem_tags or ev.problem_level == Level.L3:
                errors.append(ErrorCode.E7_FSM)
                why.append("cycle-/transaction-level comparison failed on FSM or system-level problem (Table 3 E7)")
        # A latch inferred by synthesis, or LATCH/CASEINCOMPLETE reported by lint, explains a
        # functional failure when nothing else does (stale value on the uncovered input).
        if ev.unintended_latch or ev.lint_counts.get("LATCH", 0) or ev.lint_counts.get("CASEINCOMPLETE", 0):
            errors.append(ErrorCode.E6_LATCH)
            why.append("latch inferred / incomplete case with failing simulation")
        primary = next((c for c in _SIM_PRIORITY if c in errors), None)
        needs_review = primary is None
        if needs_review:
            why.append("functional failure without taxonomy evidence – teacher review required")
        return Classification(Stage.SIMULATION, _dedupe(errors), primary, needs_review, why)

    # ---- stage 4: synthesis -------------------------------------------- #
    if not ev.synth_ok or ev.unintended_latch or ev.post_synth_mismatch:
        if ev.unintended_latch:
            errors.append(ErrorCode.E6_LATCH)
            why.append("synthesis inferred latch not required by spec")
        if (not ev.synth_ok and ev.sim_only_hits) or ev.post_synth_mismatch:
            errors.append(ErrorCode.E9_SIM_ONLY_CONSTRUCT)
            why.append(f"simulation-only constructs {ev.sim_only_hits} caused synth error / post-synth mismatch")
        if not errors:
            why.append("synthesis error without taxonomy evidence – teacher review required")
            return Classification(Stage.SYNTHESIS, [], None, True, why)
        primary = ErrorCode.E6_LATCH if ErrorCode.E6_LATCH in errors else ErrorCode.E9_SIM_ONLY_CONSTRUCT
        return Classification(Stage.SYNTHESIS, _dedupe(errors), primary, False, why)

    return Classification(Stage.PASSED, [], None, False, ["all stages passed"])


def _dedupe(codes: list[ErrorCode]) -> list[ErrorCode]:
    seen: list[ErrorCode] = []
    for c in codes:
        if c not in seen:
            seen.append(c)
    return seen
