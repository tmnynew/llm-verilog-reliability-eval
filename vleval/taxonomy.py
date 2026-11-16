"""Error taxonomy rules (paper Table 2 and §2.4).

The classifier is deliberately *evidence based*: every code it emits is tied
to an observable produced by a tool or by the testbench.  A functional
failure whose only evidence is "output differs from the reference" is put in
E10 (general functional logic error) instead of being forced into a finer
category; such samples are flagged ``needs_review`` because their finer
attribution is left to a human reader (Experiment 1; two-rater Kappa, see
:mod:`vleval.stats`).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .models import ErrorCode, Level, Stage

#: Bumped whenever the rules change, so that stored verdicts can be told apart (see ``vleval reclassify``).
TAXONOMY_VERSION = 2

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
#: ("事务级断言定位的类别优先").  E10 is only emitted when nothing else is, and
#: lint-only latch hints (E6 after E10) never become the primary error.
_SIM_PRIORITY = [
    ErrorCode.E8_PROTOCOL,
    ErrorCode.E4_RESET,
    ErrorCode.E7_FSM,
    ErrorCode.E3_ASSIGNMENT_SEMANTICS,
    ErrorCode.E5_WIDTH,
    ErrorCode.E10_GENERAL_FUNCTIONAL,
    ErrorCode.E6_LATCH,  # latch confirmed by the synthesis report on a sample that also fails simulation
]

#: Rationale strings (also used by :func:`reclassify_stored` to recognise verdicts judged with older rules).
WHY_E10 = "output mismatch without tag / lint / synthesis evidence → E10 (finer attribution left to review)"
WHY_LATCH_SYNTH = "latch reported by synthesis on a sample that fails simulation"
WHY_LATCH_LINT = "lint LATCH/CASEINCOMPLETE with failing simulation (secondary hint)"
_V1_WHY_FALLBACK_E7 = "cycle-/transaction-level comparison failed on FSM or system-level problem (Table 3 E7)"
_V1_WHY_NEEDS_REVIEW = "functional failure without taxonomy evidence – teacher review required"
_V1_WHY_LATCH = "latch inferred / incomplete case with failing simulation"


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
    problem_tags: list[str] = field(default_factory=list)  # recorded for reference; the rules never guess from the problem type


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
        # A latch found by the synthesis report is tool evidence in its own right (Table 2, E6).
        if ev.unintended_latch:
            errors.append(ErrorCode.E6_LATCH)
            why.append(WHY_LATCH_SYNTH)
        # Nothing but "the output differs from the reference": E10 on every level.  No guess is made
        # from the problem type (an untagged mismatch on an FSM problem is not necessarily an FSM bug).
        if not errors:
            errors.append(ErrorCode.E10_GENERAL_FUNCTIONAL)
            why.append(WHY_E10)
        # LATCH/CASEINCOMPLETE reported by lint alone is kept as a secondary hint only.
        if not ev.unintended_latch and (ev.lint_counts.get("LATCH", 0) or ev.lint_counts.get("CASEINCOMPLETE", 0)):
            errors.append(ErrorCode.E6_LATCH)
            why.append(WHY_LATCH_LINT)
        errors = _dedupe(errors)
        primary = next(c for c in _SIM_PRIORITY if c in errors)
        needs_review = primary == ErrorCode.E10_GENERAL_FUNCTIONAL
        return Classification(Stage.SIMULATION, errors, primary, needs_review, why)

    # ---- stage 4: synthesis -------------------------------------------- #
    if not ev.synth_ok or ev.unintended_latch or ev.post_synth_mismatch:
        if ev.unintended_latch:
            errors.append(ErrorCode.E6_LATCH)
            why.append("synthesis inferred latch not required by spec")
        if (not ev.synth_ok and ev.sim_only_hits) or ev.post_synth_mismatch:
            errors.append(ErrorCode.E9_SIM_ONLY_CONSTRUCT)
            why.append(f"simulation-only constructs {ev.sim_only_hits} with synthesis error")
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


def reclassify_stored(stage: str, errors: list[str], primary: str | None, rationale: str,
                      unintended_latch: bool) -> tuple[list[str], str | None, str, bool] | None:
    """Bring a verdict judged with the version-1 rules to the current rules without re-running any tool.

    Version 1 put an untagged functional failure in E7 when the problem was an FSM / system-level one and
    left it unclassified otherwise; both are E10 now.  The stored rationale tells which rule fired, so the
    conversion is exact.  Returns ``(errors, primary, rationale, needs_review)`` or ``None`` when the stored
    verdict already follows the current rules.
    """
    if stage != Stage.SIMULATION.value:
        return None
    parts = [p for p in rationale.split("; ") if p]
    fallback, unclassified = _V1_WHY_FALLBACK_E7 in parts, _V1_WHY_NEEDS_REVIEW in parts
    if not (fallback or unclassified or _V1_WHY_LATCH in parts):
        return None
    codes = list(errors)
    if fallback:  # the fallback only fired when no other code had been found, so this E7 carries no tag evidence
        codes = [c for c in codes if c != ErrorCode.E7_FSM.value]
    new_parts = [p for p in parts if p not in (_V1_WHY_FALLBACK_E7, _V1_WHY_NEEDS_REVIEW, _V1_WHY_LATCH)]
    had_latch_code = ErrorCode.E6_LATCH.value in codes
    codes = [c for c in codes if c != ErrorCode.E6_LATCH.value]
    if had_latch_code and unintended_latch:
        codes.append(ErrorCode.E6_LATCH.value)
        new_parts.append(WHY_LATCH_SYNTH)
    if not codes:
        codes.append(ErrorCode.E10_GENERAL_FUNCTIONAL.value)
        new_parts.append(WHY_E10)
    if had_latch_code and not unintended_latch:
        codes.append(ErrorCode.E6_LATCH.value)
        new_parts.append(WHY_LATCH_LINT)
    new_primary = next(c.value for c in _SIM_PRIORITY if c.value in codes)
    return codes, new_primary, "; ".join(new_parts), new_primary == ErrorCode.E10_GENERAL_FUNCTIONAL.value
