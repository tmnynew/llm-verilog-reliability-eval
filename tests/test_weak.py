import json
from pathlib import Path

from vleval.benchmark import Benchmark
from vleval.weak import WEAK_TARGET, escape_candidates, select_escapes, write_escapes

ROOT = Path(__file__).resolve().parents[1]


def _rec(sample_id, model, rounds, raw="```verilog\nmodule m; endmodule\n```", code="module m_final; endmodule"):
    return {
        "sample_id": sample_id,
        "problem_id": "uart",
        "model": model,
        "spec_version": "detailed",
        "strategy": "zero",
        "idx": sample_id,
        "raw_response": raw,
        "code": code,
        "rounds": rounds,
    }


def _round(stage, passed=False, primary="E8", cases=("TB_FAIL tag=proto case=1 exp=1 got=0",)):
    return {"stage": stage, "passed": passed, "primary_error": primary, "failed_cases": list(cases), "code": None}


# ----------------------------------------------------------------- candidates
def test_escape_candidates_take_initial_and_final_failed_code_and_dedupe():
    samples = [
        # failed in simulation, repaired code also failed -> two candidates (round 0 and round 2)
        _rec(1, "Model A", [_round("simulation"), _round("simulation"), _round("simulation")]),
        # passed after one repair -> only the initial code is a candidate
        _rec(2, "Model B", [_round("simulation"), _round("passed", passed=True)], raw="```verilog\nmodule m2; endmodule\n```"),
        # compile failure -> not a candidate
        _rec(3, "Model B", [_round("compile", primary="E2")]),
        # other problem
        {**_rec(4, "Model C", [_round("simulation")]), "problem_id": "sync_fifo"},
        # identical initial code to sample 1 -> dropped as duplicate
        _rec(5, "Model D", [_round("simulation")], code="module dup; endmodule"),
    ]
    c = escape_candidates(samples, "uart")
    assert [(x.sample_id, x.round) for x in c] == [(1, 0), (1, 2), (2, 0)]
    assert c[0].code.startswith("module m;") and c[1].code == "module m_final; endmodule"
    assert c[0].primary_error == "E8" and c[0].failed_cases[0].startswith("TB_FAIL")


# ----------------------------------------------------------------- selection
def test_select_escapes_interleaves_models_and_is_deterministic():
    samples = [_rec(i, f"Model {'AB'[i % 2]}", [_round("simulation")], code=f"module m{i}; endmodule") for i in range(20)]
    for s in samples:
        s["raw_response"] = f"```verilog\n{s['code']}\n```"
    cands = escape_candidates(samples, "uart")
    assert len(cands) == 20
    passes = lambda code: "m1" not in code  # noqa: E731  - reject m1, m10..m19
    sel1, tested1 = select_escapes(cands, passes, n=4, seed=7)
    sel2, _ = select_escapes(cands, passes, n=4, seed=7)
    assert [x.sample_id for x in sel1] == [x.sample_id for x in sel2]
    assert len(sel1) == 4 and tested1 >= 4
    assert {x.model for x in sel1} == {"Model A", "Model B"}
    assert all(passes(x.code) for x in sel1)
    sel3, tested3 = select_escapes(cands, lambda _c: False, n=4)
    assert sel3 == [] and tested3 == 20


def test_write_escapes_creates_files_and_index(tmp_path):
    class P:  # minimal stand-in for Problem
        escapes_dir = tmp_path / "escapes"

    (P.escapes_dir).mkdir()
    (P.escapes_dir / "e99.v").write_text("stale", encoding="utf-8")
    samples = [_rec(i, "Model A", [_round("simulation")], raw=f"```verilog\nmodule m{i}; endmodule\n```") for i in range(2)]
    cands = escape_candidates(samples, "uart")
    write_escapes(P, cands)
    files = sorted(p.name for p in P.escapes_dir.iterdir())
    assert files == ["e01.v", "e02.v", "index.json"]
    idx = json.loads((P.escapes_dir / "index.json").read_text(encoding="utf-8"))
    assert idx[0]["file"] == "e01.v" and idx[0]["round"] == 0 and idx[0]["full_tb_primary_error"] == "E8"
    assert (P.escapes_dir / "e01.v").read_text(encoding="utf-8") == "module m0; endmodule\n"


# ----------------------------------------------------------------- shipped material
def test_every_l2_l3_problem_ships_weak_testbench_and_escapes():
    bench = Benchmark(ROOT / "benchmark")
    for p in bench:
        if p.level.value == "L1":
            assert not p.weak_testbench_path.exists(), p.id
            continue
        tb = p.weak_testbench_path.read_text(encoding="utf-8")
        assert f"module {p.tb_top}" in tb, p.id
        assert "TB_RESULT" in tb and "Weak testbench" in tb, p.id
        idx = json.loads((p.escapes_dir / "index.json").read_text(encoding="utf-8"))
        assert 1 <= len(idx) <= 10, p.id
        for e in idx:
            assert (p.escapes_dir / e["file"]).exists(), (p.id, e["file"])
        assert len({e["sample_id"] for e in idx}) >= 1
    assert 0.0 < WEAK_TARGET[0] < WEAK_TARGET[1] <= 1.0
