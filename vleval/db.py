"""SQLite persistence for samples and verdicts.

Schema is intentionally flat so that teachers can query it directly
(``sqlite3 results.db``) or export to CSV for the students' analysis tasks.
"""

from __future__ import annotations

import json
import sqlite3
from collections.abc import Iterator
from pathlib import Path

from .models import ErrorCode, Sample, SpecVersion, Stage, Strategy, Verdict

_SCHEMA = """
CREATE TABLE IF NOT EXISTS samples (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    model         TEXT NOT NULL,
    model_version TEXT,
    problem_id    TEXT NOT NULL,
    spec_version  TEXT NOT NULL,
    strategy      TEXT NOT NULL,
    idx           INTEGER NOT NULL,
    temperature   REAL,
    created_at    TEXT,
    prompt        TEXT,
    raw_response  TEXT,
    code          TEXT,
    UNIQUE(model, problem_id, spec_version, strategy, idx)
);
CREATE TABLE IF NOT EXISTS verdicts (
    sample_id        INTEGER NOT NULL REFERENCES samples(id) ON DELETE CASCADE,
    round            INTEGER NOT NULL,
    stage            TEXT NOT NULL,
    passed           INTEGER NOT NULL,
    sim_passed       INTEGER NOT NULL,
    synth_ok         INTEGER NOT NULL,
    unintended_latch INTEGER NOT NULL,
    primary_error    TEXT,
    errors           TEXT,           -- JSON list
    lint_density     REAL,
    lint_counts      TEXT,           -- JSON
    failed_cases     TEXT,           -- JSON
    resources        TEXT,           -- JSON
    tool_disagreement INTEGER,
    tool_logs        TEXT,           -- JSON
    code             TEXT,           -- code judged in this round (NULL in pre-2026-10 databases)
    raw_response     TEXT,           -- model reply the code was extracted from
    PRIMARY KEY(sample_id, round)
);
CREATE TABLE IF NOT EXISTS annotations (   -- two-rater review of primary errors (Kappa)
    sample_id  INTEGER NOT NULL REFERENCES samples(id),
    rater      TEXT NOT NULL,
    primary_error TEXT,
    note       TEXT,
    PRIMARY KEY(sample_id, rater)
);
"""


class ResultStore:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(self.path, check_same_thread=False)
        self.conn.execute("PRAGMA foreign_keys=ON")
        self.conn.executescript(_SCHEMA)
        self._migrate()

    def _migrate(self) -> None:
        """Add columns introduced after the first release to databases created earlier."""
        have = {row[1] for row in self.conn.execute("PRAGMA table_info(verdicts)")}
        with self.conn:
            for col in ("code", "raw_response"):
                if col not in have:
                    self.conn.execute(f"ALTER TABLE verdicts ADD COLUMN {col} TEXT")

    # ---- write --------------------------------------------------------- #
    def exists(self, model: str, problem_id: str, spec: SpecVersion, strategy: Strategy, idx: int) -> bool:
        row = self.conn.execute(
            "SELECT 1 FROM samples WHERE model=? AND problem_id=? AND spec_version=? AND strategy=? AND idx=?",
            (model, problem_id, spec.value, strategy.value, idx),
        ).fetchone()
        return row is not None

    def add(self, s: Sample) -> int:
        with self.conn:
            cur = self.conn.execute(
                "INSERT OR REPLACE INTO samples(model, model_version, problem_id, spec_version, strategy, idx, temperature, created_at, prompt, raw_response, code) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (
                    s.model,
                    s.model_version,
                    s.problem_id,
                    s.spec_version.value,
                    s.strategy.value,
                    s.index,
                    s.temperature,
                    s.created_at,
                    s.prompt,
                    s.raw_response,
                    s.code,
                ),
            )
            sid = cur.lastrowid
            self.conn.execute("DELETE FROM verdicts WHERE sample_id=?", (sid,))
            for r, v in enumerate(s.rounds):
                self.conn.execute(
                    "INSERT INTO verdicts(sample_id, round, stage, passed, sim_passed, synth_ok, unintended_latch, primary_error, errors, "
                    "lint_density, lint_counts, failed_cases, resources, tool_disagreement, tool_logs, code, raw_response) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (
                        sid,
                        r,
                        v.stage.value,
                        int(v.passed),
                        int(v.sim_passed),
                        int(v.synth_ok),
                        int(v.unintended_latch),
                        v.primary_error.value if v.primary_error else None,
                        json.dumps([e.value for e in v.errors]),
                        v.lint_density,
                        json.dumps(v.lint_counts),
                        json.dumps(v.failed_cases, ensure_ascii=False),
                        json.dumps(v.resources),
                        int(v.tool_disagreement),
                        json.dumps(v.tool_logs, ensure_ascii=False),
                        v.code,
                        v.raw_response,
                    ),
                )
        return int(sid)

    def annotate(self, sample_id: int, rater: str, primary_error: str | None, note: str = "") -> None:
        with self.conn:
            self.conn.execute("INSERT OR REPLACE INTO annotations VALUES (?,?,?,?)", (sample_id, rater, primary_error, note))

    # ---- read ---------------------------------------------------------- #
    def samples(self, model: str | None = None) -> Iterator[Sample]:
        q = "SELECT * FROM samples" + (" WHERE model=?" if model else "") + " ORDER BY id"
        self.conn.row_factory = sqlite3.Row
        for row in self.conn.execute(q, (model,) if model else ()):
            s = Sample(
                problem_id=row["problem_id"],
                model=row["model"],
                spec_version=SpecVersion(row["spec_version"]),
                strategy=Strategy(row["strategy"]),
                index=row["idx"],
                prompt=row["prompt"],
                raw_response=row["raw_response"],
                code=row["code"],
                model_version=row["model_version"] or "",
                created_at=row["created_at"] or "",
                temperature=row["temperature"] or 0.2,
            )
            for v in self.conn.execute("SELECT * FROM verdicts WHERE sample_id=? ORDER BY round", (row["id"],)):
                s.rounds.append(
                    Verdict(
                        stage=Stage(v["stage"]),
                        passed=bool(v["passed"]),
                        sim_passed=bool(v["sim_passed"]),
                        synth_ok=bool(v["synth_ok"]),
                        unintended_latch=bool(v["unintended_latch"]),
                        errors=[ErrorCode(e) for e in json.loads(v["errors"] or "[]")],
                        primary_error=ErrorCode(v["primary_error"]) if v["primary_error"] else None,
                        lint_density=v["lint_density"],
                        lint_counts=json.loads(v["lint_counts"] or "{}"),
                        failed_cases=json.loads(v["failed_cases"] or "[]"),
                        resources=json.loads(v["resources"] or "{}"),
                        tool_disagreement=bool(v["tool_disagreement"]),
                        tool_logs=json.loads(v["tool_logs"] or "{}"),
                        code=v["code"],
                        raw_response=v["raw_response"],
                    )
                )
            yield s

    def annotations(self) -> list[tuple]:
        return list(self.conn.execute("SELECT sample_id, rater, primary_error FROM annotations ORDER BY sample_id, rater"))

    def export_jsonl(self, path: Path) -> int:
        n = 0
        with open(path, "w", encoding="utf-8") as f:
            for s in self.samples():
                f.write(s.to_json() + "\n")
                n += 1
        return n
