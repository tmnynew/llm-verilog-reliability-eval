import csv
import json

from vleval.db import ResultStore
from vleval.export import export_dataset, redact_text, residual_paths
from vleval.models import ErrorCode, Sample, SpecVersion, Stage, Strategy, Verdict


# ----------------------------------------------------------------- redaction
def test_redact_workspace_home_tmp_and_tools():
    text = (
        r"D:\lab_file6\verilog-llm-evalab\benchmark\L3\uart\tb.v:36: $finish; "
        r"C:\Users\someone\AppData\Local\Temp\vleval_uart_ab12cd\dut.v:19:26: warn; "
        r"\Local\Temp\vleval_fifo_x9\dut.v:3; "
        r"C:\Xilinx\Vivado\2024.1\bin\vivado.bat; C:\tools\oss-cad-suite\bin\yosys; C:\Users\someone\x.txt"
    )
    out = redact_text(text)
    assert "<repo>\\benchmark\\L3\\uart\\tb.v" in out
    assert "<tmp>\\dut.v:19:26" in out and "<tmp>\\dut.v:3" in out
    assert "<vivado>\\bin" in out and "<oss-cad-suite>\\bin" in out and "<home>\\x.txt" in out
    assert "someone" not in out and "lab_file6" not in out
    assert residual_paths(out) == []


def test_redact_handles_json_escaped_backslashes_and_forward_slashes():
    out = redact_text(json.dumps({"p": r"D:\lab_file6\verilog-llm-evalab\x.v"}) + " D:/lab_file6/verilog-llm-evalab/y.v")
    assert "lab_file6" not in out and out.count("<repo>") == 2


# ----------------------------------------------------------------- export
def _sample(idx: int, passed_after: int | None) -> Sample:
    s = Sample(
        problem_id="sync_fifo",
        model="Model T",
        spec_version=SpecVersion.DETAILED,
        strategy=Strategy.ZERO_SHOT,
        index=idx,
        prompt="p",
        raw_response="```verilog\nmodule sync_fifo; endmodule\n```",
        code="module sync_fifo; endmodule",
        model_version="t-1",
        created_at="2026-10-02",
    )
    rounds = 1 if passed_after is None else passed_after + 1
    for r in range(rounds):
        ok = passed_after is not None and r == passed_after
        s.rounds.append(
            Verdict(
                stage=Stage.PASSED if ok else Stage.SIMULATION,
                passed=ok,
                sim_passed=ok,
                synth_ok=ok,
                errors=[] if ok else [ErrorCode.E8_PROTOCOL],
                primary_error=None if ok else ErrorCode.E8_PROTOCOL,
                lint_density=0.5,
                failed_cases=[] if ok else [r"C:\Users\u\AppData\Local\Temp\vleval_sync_fifo_q\dut.v:5: TB_FAIL tag=proto"],
                resources={"LUT": 20, "FF": 21, "Fmax_MHz": 250.0} if ok else {},
                tool_logs={"sim": r"D:\lab_file6\verilog-llm-evalab\benchmark\L3\sync_fifo\tb.v:9", "needs_review": False},
            )
        )
    return s


def test_export_dataset_files_and_counts(tmp_path):
    store = ResultStore(tmp_path / "r.db")
    store.add(_sample(0, None))  # never passes, 1 round
    store.add(_sample(1, 2))  # repaired in round 2 -> 3 rounds
    store.add(_sample(2, 0))  # passes initially
    store.conn.close()

    bench = tmp_path / "benchmark"
    (bench / "L3" / "sync_fifo").mkdir(parents=True)
    st = export_dataset(tmp_path / "r.db", tmp_path / "data", benchmark_root=bench)
    assert (st.samples, st.verdicts, st.residual_paths) == (3, 5, 0)

    lines = [json.loads(x) for x in (tmp_path / "data" / "samples.jsonl").read_text(encoding="utf-8").splitlines()]
    assert len(lines) == 3 and lines[0]["level"] == "L3" and len(lines[1]["rounds"]) == 3
    assert "lab_file6" not in (tmp_path / "data" / "samples.jsonl").read_text(encoding="utf-8")
    assert "lab_file6" not in (tmp_path / "data" / "tool_logs.jsonl").read_text(encoding="utf-8")

    with open(tmp_path / "data" / "samples.csv", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    by_idx = {int(r["idx"]): r for r in rows}
    assert by_idx[0]["final_passed"] == "0" and by_idx[0]["repaired"] == "0"
    assert by_idx[1]["final_passed"] == "1" and by_idx[1]["repaired"] == "1" and by_idx[1]["n_rounds"] == "3"
    assert by_idx[2]["repaired"] == "0" and by_idx[2]["final_LUT"] == "20"

    with open(tmp_path / "data" / "verdicts.csv", encoding="utf-8", newline="") as f:
        vrows = list(csv.DictReader(f))
    assert len(vrows) == 5 and {r["primary_error"] for r in vrows} == {"", "E8"}

    manifest = json.loads((tmp_path / "data" / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["samples"] == 3 and manifest["residual_local_paths"] == 0 and "samples.jsonl" in manifest["files"]


# ----------------------------------------------------------------- per-round code
def test_per_round_code_round_trips_and_old_db_is_migrated(tmp_path):
    import sqlite3

    # a database created before verdicts.code / raw_response existed
    old = tmp_path / "old.db"
    con = sqlite3.connect(old)
    con.executescript(
        """
        CREATE TABLE samples (id INTEGER PRIMARY KEY AUTOINCREMENT, model TEXT NOT NULL, model_version TEXT, problem_id TEXT NOT NULL,
            spec_version TEXT NOT NULL, strategy TEXT NOT NULL, idx INTEGER NOT NULL, temperature REAL, created_at TEXT,
            prompt TEXT, raw_response TEXT, code TEXT, UNIQUE(model, problem_id, spec_version, strategy, idx));
        CREATE TABLE verdicts (sample_id INTEGER NOT NULL, round INTEGER NOT NULL, stage TEXT NOT NULL, passed INTEGER NOT NULL,
            sim_passed INTEGER NOT NULL, synth_ok INTEGER NOT NULL, unintended_latch INTEGER NOT NULL, primary_error TEXT, errors TEXT,
            lint_density REAL, lint_counts TEXT, failed_cases TEXT, resources TEXT, tool_disagreement INTEGER, tool_logs TEXT,
            PRIMARY KEY(sample_id, round));
        INSERT INTO samples(model, model_version, problem_id, spec_version, strategy, idx, prompt, raw_response, code)
            VALUES ('Model T', 't', 'sync_fifo', 'detailed', 'zero', 0, 'p', 'r', 'module sync_fifo; endmodule');
        INSERT INTO verdicts VALUES (1, 0, 'passed', 1, 1, 1, 0, NULL, '[]', 0.0, '{}', '[]', '{}', 0, '{}');
        """
    )
    con.commit()
    con.close()

    store = ResultStore(old)  # migrates in place
    cols = {r[1] for r in store.conn.execute("PRAGMA table_info(verdicts)")}
    assert {"code", "raw_response"} <= cols
    old_sample = next(store.samples())
    assert old_sample.rounds[0].code is None  # legacy record: nothing recorded

    s = _sample(7, 1)
    s.rounds[0].code, s.rounds[0].raw_response = "module a; endmodule", "r0"
    s.rounds[1].code, s.rounds[1].raw_response = "module b; endmodule", "r1"
    store.add(s)
    got = [x for x in store.samples() if x.index == 7][0]
    assert [r.code for r in got.rounds] == ["module a; endmodule", "module b; endmodule"]
    assert got.rounds[1].raw_response == "r1"
    store.conn.close()

    export_dataset(old, tmp_path / "d2", benchmark_root=tmp_path / "nobench")
    lines = [json.loads(x) for x in (tmp_path / "d2" / "samples.jsonl").read_text(encoding="utf-8").splitlines()]
    assert lines[0]["rounds"][0]["code"] is None
    assert lines[1]["rounds"][1]["code"] == "module b; endmodule"
