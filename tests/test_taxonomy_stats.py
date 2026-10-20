import math

import pytest

from vleval.models import ErrorCode, Level, Stage
from vleval.stats import cohen_kappa, fisher_exact, lint_density, pass_at_k, repair_curve, wilson_ci
from vleval.taxonomy import Evidence, classify
from vleval.tools.tbproto import parse_tb_output


# ----------------------------------------------------------------- taxonomy
def test_interface_failure_is_e1():
    c = classify(Evidence(interface_ok=False, interface_issues=["missing port x"]))
    assert c.stage == Stage.INTERFACE and c.primary == ErrorCode.E1_INTERFACE


def test_compile_failure_is_e2():
    c = classify(Evidence(interface_ok=True, compile_ok=False, sv_constructs={"logic": 2}))
    assert c.primary == ErrorCode.E2_LANGUAGE_SUBSET and "SystemVerilog" in c.rationale[0]


def test_sim_failure_multilabel_and_priority():
    ev = Evidence(interface_ok=True, sim_ok=False, failed_tags=["reset", "func"], lint_counts={"WIDTH": 2}, problem_level=Level.L2)
    c = classify(ev)
    assert set(c.errors) == {ErrorCode.E4_RESET, ErrorCode.E5_WIDTH}
    assert c.primary == ErrorCode.E4_RESET  # reset transaction beats lint-based width evidence
    assert not c.needs_review


def test_protocol_tag_wins_in_sim_stage():
    ev = Evidence(interface_ok=True, sim_ok=False, failed_tags=["func", "proto"], lint_counts={"BLKSEQ": 1}, problem_level=Level.L3)
    c = classify(ev)
    assert c.primary == ErrorCode.E8_PROTOCOL and ErrorCode.E3_ASSIGNMENT_SEMANTICS in c.errors


def test_sim_failure_without_evidence_needs_review():
    c = classify(Evidence(interface_ok=True, sim_ok=False, failed_tags=["func"], problem_level=Level.L1))
    assert c.stage == Stage.SIMULATION and c.primary is None and c.needs_review


def test_incomplete_case_latch_explains_sim_failure():
    c = classify(Evidence(interface_ok=True, sim_ok=False, failed_tags=["func"], lint_counts={"CASEINCOMPLETE": 1, "LATCH": 1}))
    assert c.primary == ErrorCode.E6_LATCH


def test_synth_stage_e6_and_e9():
    c = classify(Evidence(interface_ok=True, unintended_latch=True))
    assert c.stage == Stage.SYNTHESIS and c.primary == ErrorCode.E6_LATCH
    c = classify(Evidence(interface_ok=True, synth_ok=False, sim_only_hits={"delay": 1}))
    assert c.primary == ErrorCode.E9_SIM_ONLY_CONSTRUCT
    c = classify(Evidence(interface_ok=True, synth_ok=False))
    assert c.primary is None and c.needs_review


def test_all_pass():
    c = classify(Evidence(interface_ok=True))
    assert c.stage == Stage.PASSED and c.errors == []


# ----------------------------------------------------------------- tb protocol
def test_parse_tb_output():
    out = "noise\nTB_FAIL tag=reset case=3 exp=0 got=1\nTB_FAIL tag=func case=9 exp=a got=b\nTB_RESULT FAIL n_fail=2 n_checks=100\n"
    o = parse_tb_output(out)
    assert not o.passed and o.n_fail == 2 and o.n_checks == 100 and o.tags == ["reset", "func"]
    ok = parse_tb_output("TB_RESULT PASS n_checks=512")
    assert ok.passed and ok.n_checks == 512
    crash = parse_tb_output("segfault", timed_out=False)
    assert crash.crashed and "crash" in crash.tags


# ----------------------------------------------------------------- stats
def test_pass_at_k():
    assert pass_at_k(10, 10, 1) == 1.0
    assert pass_at_k(10, 0, 5) == 0.0
    assert math.isclose(pass_at_k(10, 3, 1), 0.3)
    assert math.isclose(pass_at_k(10, 3, 5), 1 - math.comb(7, 5) / math.comb(10, 5))


def test_wilson_ci():
    lo, hi = wilson_ci(50, 100)
    assert 0.40 < lo < 0.41 and 0.59 < hi < 0.60
    assert wilson_ci(0, 0) == (0.0, 0.0)


def test_fisher_exact_matches_known_value():
    # classic tea-tasting table
    p = fisher_exact(3, 1, 1, 3)
    assert math.isclose(p, 0.4857, abs_tol=1e-3)
    assert fisher_exact(50, 50, 50, 50) > 0.99


def test_cohen_kappa():
    assert cohen_kappa(list("aabb"), list("aabb")) == 1.0
    assert cohen_kappa(list("aabb"), list("abab")) == 0.0
    with pytest.raises(ValueError):
        cohen_kappa([], [])


def test_lint_density_and_repair_curve():
    assert lint_density(3, 60) == 5.0
    assert lint_density(3, 0) == 0.0
    assert repair_curve([0, 1, 3, -1], 3) == [0.25, 0.5, 0.5, 0.75]
