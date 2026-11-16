"""Report tables on a synthetic result set (no EDA tools, no network)."""

import csv
import json

from vleval.db import ResultStore
from vleval.export import export_dataset, load_samples
from vleval.models import ErrorCode, Sample, SpecVersion, Stage, Strategy, Verdict
from vleval.report import Rejudge, Report

V1_FALLBACK = "cycle-/transaction-level comparison failed on FSM or system-level problem (Table 3 E7)"
V1_REVIEW = "functional failure without taxonomy evidence – teacher review required"


def _verdict(kind: str) -> Verdict:
    if kind == "pass":
        return Verdict(stage=Stage.PASSED, passed=True, sim_passed=True, synth_ok=True, lint_density=0.0, resources={"LUT": 10, "FF": 4, "Fmax_MHz": 300.0})
    if kind == "compile":
        return Verdict(stage=Stage.COMPILE, passed=False, errors=[ErrorCode.E2_LANGUAGE_SUBSET], primary_error=ErrorCode.E2_LANGUAGE_SUBSET)
    code = ErrorCode(kind)
    return Verdict(stage=Stage.SIMULATION, passed=False, synth_ok=True, errors=[code], primary_error=code, lint_density=1.0)


def _add(store: ResultStore, model: str, pid: str, kinds: list[list[str]], spec=SpecVersion.DETAILED, strategy=Strategy.ZERO_SHOT) -> list[int]:
    ids = []
    for idx, rounds in enumerate(kinds):
        s = Sample(problem_id=pid, model=model, spec_version=spec, strategy=strategy, index=idx, prompt="p", raw_response="r", code="module m; endmodule")
        s.rounds = [_verdict(k) for k in rounds]
        ids.append(store.add(s))
    return ids


def _build(tmp_path):
    store = ResultStore(tmp_path / "r.db")
    ids = {}
    # Model X: detailed spec – L1 problem 2/2, L2 problem 1/2 (one E7 repaired in round 1), L3 problem 0/2 (E8, E10)
    ids["x_l1"] = _add(store, "Model X", "parity_gen8", [["pass"], ["pass"]])
    ids["x_l2"] = _add(store, "Model X", "ring_counter", [["pass"], ["E7", "pass"]])
    ids["x_l3"] = _add(store, "Model X", "sync_fifo", [["E8", "E8"], ["E10", "E10"]])
    # Model X: brief spec – everything fails to compile except one L1 sample
    _add(store, "Model X", "parity_gen8", [["pass"], ["compile"]], spec=SpecVersion.BRIEF)
    _add(store, "Model X", "ring_counter", [["compile"], ["compile"]], spec=SpecVersion.BRIEF)
    _add(store, "Model X", "sync_fifo", [["compile"], ["compile"]], spec=SpecVersion.BRIEF)
    # Model Y: only the baseline configuration, compile failures on the L1 problem
    ids["y_l1"] = _add(store, "Model Y", "parity_gen8", [["compile"], ["compile"]])
    _add(store, "Model Y", "ring_counter", [["pass"], ["pass"]])
    _add(store, "Model Y", "sync_fifo", [["E8"], ["pass"]])
    return store, ids


def test_tables_follow_the_manuscript(bench, tmp_path):
    store, _ = _build(tmp_path)
    rep = Report(store.samples(), bench, pool=["Model X", "Model Y"])
    t = rep.build()
    assert list(t) == ["T4_passk", "T4_tests", "T5_synth", "F4_errors", "T6_prompt", "F5_repair", "resources", "problems"]
    assert "| Model X | L2 | 1 | 2 | 50.0 |" in t["T4_passk"] and "| Model Y | L1 | 1 | 2 | 0.0 |" in t["T4_passk"]
    # ten categories, E10 counted as a primary error
    assert "E10 一般功能逻辑错误" in t["F4_errors"] and rep.data["errors"]["L3"]["E10"] == 1 and rep.data["errors"]["L3"]["E8"] == 2
    assert rep.data["errors"]["L1"]["E2"] == 2 and rep.data["errors"]["L3"]["unclassified"] == 0
    # specification effect is only reported for the model that ran both versions; paired over 3 problems
    assert "| Model X | zero | 16.7 | 50.0 | +33.3 | 2 / 0 / 1 |" in t["T6_prompt"] and "Model Y" not in t["T6_prompt"].split("同一规范版本")[0]
    assert rep.data["prompt"]["Model X/zero"]["p"] == 0.5  # 2 informative problems, same sign → 2 / 2^2
    # repair: Model X all-sample curve 50 → 66.7; E7 1/1 repaired, E8 0/1, E10 0/1; pooled row first
    assert rep.data["repair"]["Model X"]["curve"][:2] == [0.5, 4 / 6]
    assert rep.data["repair"]["Model X"]["E7"] == [1, 1] and rep.data["repair"]["Model X"]["E10"] == [0, 1]
    assert rep.data["repair"]["合并（Model X、Model Y）"]["E8"] == [0, 2]
    assert "| sync_fifo | 0/2 | 1/2 |" in t["problems"]
    rep.write(tmp_path / "out", figures=False)
    assert (tmp_path / "out" / "tables.md").exists() and not list((tmp_path / "out").glob("*.png"))
    assert json.loads((tmp_path / "out" / "summary.json").read_text(encoding="utf-8"))["passk"]["Model X/L1"]["pass1"] == 1.0


def test_vivado_criterion_and_weak_tb_from_rejudge_data(bench, tmp_path):
    store, ids = _build(tmp_path)
    rj = tmp_path / "rejudge"
    rj.mkdir()
    a, b = ids["y_l1"]
    with open(rj / "vivado_recheck.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerows([["sample_id", "vivado_synth_ok"], [a, 1], [b, 0]])
    with open(rj / "vivado_recheck_xsim.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerows([["sample_id", "xsim_pass", "vivado_latch"], [a, 1, 0]])
    with open(rj / "weak_tb_escape_rate.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerows([["sample_id", "weak_tb_pass"], [ids["x_l2"][1], 1], [ids["x_l3"][0], 0], [ids["x_l3"][1], 1]])
    rep = Report(store.samples(), bench, rejudge=Rejudge(rj))
    t = rep.build()
    # Model Y: 2 compile failures, 1 accepted by Vivado and functionally correct → synthesizable 4/6 → 5/6, pass@1 3/6 → 4/6
    assert "| Model Y | 2 | 1 | 1 | 66.7 → 83.3 | 50.0 → 66.7 |" in t["T5_synth"]
    assert rep.data["weak_tb"]["L2 + L3"] == [2, 3] and rep.data["weak_tb"]["L3"] == [1, 2]
    # without re-judging data the extra tables are simply absent
    plain = Report(store.samples(), bench, rejudge=Rejudge(tmp_path / "missing")).build()
    assert "weak_tb" not in plain and "Vivado 接受" not in plain["T5_synth"]
    # a design that synthesises but fails implementation (e.g. a multiply driven net) is not accepted by Vivado
    with open(rj / "vivado_recheck.csv", "w", encoding="utf-8", newline="") as f:
        csv.writer(f).writerows([["sample_id", "vivado_synth_ok", "vivado_impl_ok"], [a, 1, 0], [b, 0, ""]])
    strict = Report(store.samples(), bench, rejudge=Rejudge(rj)).build()
    assert "| Model Y | 2 | 0 | 0 | 66.7 → 66.7 | 50.0 → 50.0 |" in strict["T5_synth"]


def test_reclassify_store_and_report_from_exported_dataset(bench, tmp_path):
    store, ids = _build(tmp_path)
    # two verdicts as written by the version-1 rules
    with store.conn:
        store.conn.execute(
            "UPDATE verdicts SET primary_error='E7', errors=?, tool_logs=? WHERE sample_id=? AND round=0",
            (json.dumps(["E7"]), json.dumps({"rationale": V1_FALLBACK, "needs_review": "False"}), ids["x_l3"][1]),
        )
        store.conn.execute(
            "UPDATE verdicts SET primary_error=NULL, errors='[]', tool_logs=? WHERE sample_id=? AND round=1",
            (json.dumps({"rationale": V1_REVIEW, "needs_review": "True"}), ids["x_l3"][1]),
        )
    assert store.reclassify(dry_run=True) == {("E7", "E10"): 1, (None, "E10"): 1}
    assert store.reclassify() == {("E7", "E10"): 1, (None, "E10"): 1}
    assert store.reclassify() == {}  # idempotent
    row = store.conn.execute("SELECT primary_error, errors, tool_logs FROM verdicts WHERE sample_id=? AND round=1", (ids["x_l3"][1],)).fetchone()
    assert row[0] == "E10" and json.loads(row[1]) == ["E10"] and json.loads(row[2])["needs_review"] == "True"
    store.conn.close()

    export_dataset(tmp_path / "r.db", tmp_path / "data", benchmark_root=bench.root)
    from_db = Report(ResultStore(tmp_path / "r.db").samples(), bench).build()
    from_text = Report(load_samples(tmp_path / "data"), bench).build()
    assert from_db == from_text  # the text release is sufficient to rebuild every table
