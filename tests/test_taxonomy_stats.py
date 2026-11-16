import math

import pytest

from vleval.models import ErrorCode, Level, Stage
from vleval.stats import (
    cluster_bootstrap_ci,
    cohen_kappa,
    fisher_exact,
    lint_density,
    paired_signflip_p,
    pass_at_k,
    repair_curve,
    two_sample_permutation_p,
    wilson_ci,
)
from vleval.taxonomy import Evidence, classify, reclassify_stored
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


def test_sim_failure_without_evidence_is_e10_on_every_level():
    for lv, tags in ((Level.L1, []), (Level.L2, ["fsm"]), (Level.L3, [])):
        c = classify(Evidence(interface_ok=True, sim_ok=False, failed_tags=["func"], problem_level=lv, problem_tags=tags))
        assert c.stage == Stage.SIMULATION and c.errors == [ErrorCode.E10_GENERAL_FUNCTIONAL]
        assert c.primary == ErrorCode.E10_GENERAL_FUNCTIONAL and c.needs_review  # finer attribution is left to a reader


def test_state_tag_is_e7_but_problem_type_alone_is_not():
    c = classify(Evidence(interface_ok=True, sim_ok=False, failed_tags=["state"], problem_level=Level.L2, problem_tags=["fsm"]))
    assert c.primary == ErrorCode.E7_FSM and not c.needs_review


def test_lint_latch_hint_is_secondary_and_synthesis_latch_is_e6():
    c = classify(Evidence(interface_ok=True, sim_ok=False, failed_tags=["func"], lint_counts={"CASEINCOMPLETE": 1, "LATCH": 1}))
    assert c.primary == ErrorCode.E10_GENERAL_FUNCTIONAL and c.errors == [ErrorCode.E10_GENERAL_FUNCTIONAL, ErrorCode.E6_LATCH]
    c = classify(Evidence(interface_ok=True, sim_ok=False, failed_tags=["func"], unintended_latch=True))
    assert c.primary == ErrorCode.E6_LATCH and c.errors == [ErrorCode.E6_LATCH] and not c.needs_review
    c = classify(Evidence(interface_ok=True, sim_ok=False, failed_tags=["proto"], unintended_latch=True, lint_counts={"LATCH": 1}))
    assert c.primary == ErrorCode.E8_PROTOCOL and c.errors == [ErrorCode.E8_PROTOCOL, ErrorCode.E6_LATCH]


def test_reclassify_stored_converts_version1_verdicts():
    v1_fallback = "cycle-/transaction-level comparison failed on FSM or system-level problem (Table 3 E7)"
    v1_review = "functional failure without taxonomy evidence – teacher review required"
    v1_latch = "latch inferred / incomplete case with failing simulation"
    # untagged failure on an FSM / L3 problem: E7 by problem type → E10
    codes, primary, why, review = reclassify_stored("simulation", ["E7"], "E7", v1_fallback, False)
    assert (codes, primary, review) == (["E10"], "E10", True) and "E10" in why and "Table 3" not in why
    # ... with a lint-only latch hint
    codes, primary, _, _ = reclassify_stored("simulation", ["E7", "E6"], "E7", v1_fallback + "; " + v1_latch, False)
    assert (codes, primary) == (["E10", "E6"], "E10")
    # formerly unclassified
    assert reclassify_stored("simulation", [], None, v1_review, False)[:2] == (["E10"], "E10")
    # E7 backed by a testbench tag stays E7; a verdict already under the current rules is left alone
    assert reclassify_stored("simulation", ["E7"], "E7", "testbench tag 'state' → E7", False) is None
    again = reclassify_stored("simulation", codes, primary, why, False)
    assert again is None
    # tag-based primary with a synthesis-confirmed latch keeps E6 as a secondary code
    codes, primary, _, review = reclassify_stored("simulation", ["E8", "E6"], "E8", "testbench tag 'proto' → E8; " + v1_latch, True)
    assert (codes, primary, review) == (["E8", "E6"], "E8", False)
    assert reclassify_stored("compile", ["E2"], "E2", "Verilog-2001 compile error", False) is None


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


def test_paired_signflip_is_exact():
    # one informative problem: both sign patterns are as extreme as the observation
    assert paired_signflip_p([0.3, 0, 0]) == 1.0
    # 5 problems all improved: only the 2 uniform patterns reach the observed |sum| → 2 / 2^5
    assert math.isclose(paired_signflip_p([0.1, 0.2, 0.3, 0.4, 0.5]), 2 / 32)
    # sign symmetry and no information at all
    assert paired_signflip_p([0.2, -0.5, 0.1]) == paired_signflip_p([-0.2, 0.5, -0.1])
    assert paired_signflip_p([0, 0]) == 1.0
    # float pass-rate differences are treated as exact fractions (0.3 - 0.1 == 0.2)
    assert math.isclose(paired_signflip_p([0.3 - 0.1, 0.2]), 0.5)


def test_two_sample_permutation():
    assert math.isclose(two_sample_permutation_p([1, 1, 1], [0, 0, 0]), 2 / 20)  # only the two extreme splits of C(6,3)
    assert two_sample_permutation_p([0.5, 0.5], [0.5, 0.5]) == 1.0
    assert two_sample_permutation_p([], [1.0]) == 1.0


def test_cluster_bootstrap_ci():
    pytest.importorskip("numpy")
    lo, hi = cluster_bootstrap_ci([1.0] * 10)
    assert lo == hi == 1.0
    lo, hi = cluster_bootstrap_ci([0.0, 1.0] * 5, n_resamples=4000)
    assert 0.1 <= lo < 0.5 < hi <= 0.9  # clustered interval is far wider than a 100-sample Wilson interval
    assert cluster_bootstrap_ci([]) == (0.0, 0.0)
    assert cluster_bootstrap_ci([0.2, 0.9, 0.4]) == cluster_bootstrap_ci([0.2, 0.9, 0.4])  # seeded


def test_cohen_kappa():
    assert cohen_kappa(list("aabb"), list("aabb")) == 1.0
    assert cohen_kappa(list("aabb"), list("abab")) == 0.0
    with pytest.raises(ValueError):
        cohen_kappa([], [])


def test_lint_density_and_repair_curve():
    assert lint_density(3, 60) == 5.0
    assert lint_density(3, 0) == 0.0
    assert repair_curve([0, 1, 3, -1], 3) == [0.25, 0.5, 0.5, 0.75]
