"""Integration tests that need a simulator (Icarus or Verilator). Skipped otherwise."""

from pathlib import Path

import pytest

from vleval.db import ResultStore
from vleval.judge import Judge
from vleval.llm import GoldenOracleClient
from vleval.models import ErrorCode, Stage
from vleval.report import Report
from vleval.runner import Runner, RunPlan
from vleval.tools import ToolConfig

from .conftest import requires_eda

pytestmark = [requires_eda, pytest.mark.eda]


@pytest.fixture(scope="module")
def judge() -> Judge:
    cfg = ToolConfig(enable_yosys=True)
    return Judge(cfg)


def test_all_goldens_pass(bench, judge):
    for p in bench:
        v = judge.judge(p, p.golden_path.read_text(encoding="utf-8"))
        assert v.passed, f"{p.id}: {v.stage} {v.failed_cases[:3]} {v.tool_logs.get('compile', '')[-300:]}"


def test_reset_polarity_bug_is_e4(bench, judge):
    p = bench.get("counter_param")
    code = p.golden_path.read_text(encoding="utf-8").replace("if (!rst_n)", "if (rst_n)")
    v = judge.judge(p, code)
    assert v.stage == Stage.SIMULATION and v.primary_error == ErrorCode.E4_RESET


def test_fifo_full_bug_is_e8(bench, judge):
    p = bench.get("sync_fifo")
    code = p.golden_path.read_text(encoding="utf-8").replace("assign full  = (count == DEPTH);", "assign full  = (count == DEPTH - 1);")
    v = judge.judge(p, code)
    assert not v.sim_passed and v.primary_error == ErrorCode.E8_PROTOCOL


def test_oracle_run_and_report(bench, tmp_path: Path, judge):
    store = ResultStore(tmp_path / "r.db")
    probs = [bench.get("parity_gen8"), bench.get("seq_detector_1011")]
    plan = RunPlan(model_name="oracle", problems=probs, n_samples=2, max_repair_rounds=0, workers=2)
    summary = Runner(GoldenOracleClient(bench), judge, store).run(plan)
    assert summary.total == 4 and summary.passed_initial == 4 and not summary.errors
    # resume skips everything
    assert Runner(GoldenOracleClient(bench), judge, store).run(plan).skipped == 4
    rep = Report(store.samples(), bench)
    tables = rep.build()
    assert "oracle" in tables["T5_passk"] and "| oracle | L1 | 2 | 100.0 |" in tables["T5_passk"]
    rep.write(tmp_path / "out")
    assert (tmp_path / "out" / "tables.md").exists()
    assert store.export_jsonl(tmp_path / "s.jsonl") == 4
