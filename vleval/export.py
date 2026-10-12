"""Export a results database as a redistributable, text-only dataset (paper data release).

Produces, under ``out_dir``::

    samples.jsonl     one line per sample: metadata, prompt, raw response, code and all
                      per-round verdicts incl. per-round code when recorded (without tool logs)
    verdicts.csv      one row per (sample, round): flat judging results for spreadsheets / pandas
    samples.csv       one row per sample: initial and final outcome (handy for pass@k, repair stats)
    tool_logs.jsonl   one line per (sample, round): compile / simulation / synthesis log excerpts
    manifest.json     counts, source DB checksum, redaction rules applied

Local file-system paths (workspace, user home, temp directories, EDA installation
directories) are replaced by placeholders so that the release carries no machine-specific
information.  Prompts, responses and code are exported verbatim.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .db import ResultStore

# --------------------------------------------------------------------------- #
# path redaction
# --------------------------------------------------------------------------- #
_SEP = r"(?:\\\\|\\|/)+"  # a path separator as it may appear in plain or JSON-escaped text
_NAME = r"[^\\/\s\"'<>|:]+"

# (pattern, placeholder, description) – order matters: specific rules first.
REDACTION_RULES: list[tuple[re.Pattern[str], str, str]] = [
    (
        re.compile(rf"[A-Za-z]:{_SEP}{_NAME}{_SEP}verilog-llm-evalab", re.I),
        "<repo>",
        "workspace checkout of this repository",
    ),
    (
        re.compile(rf"(?:[A-Za-z]:)?{_SEP}(?:Users{_SEP}{_NAME}{_SEP})?(?:AppData{_SEP})?Local{_SEP}Temp{_SEP}vleval_{_NAME}", re.I),
        "<tmp>",
        "per-sample temporary working directory",
    ),
    (
        re.compile(rf"[A-Za-z]:{_SEP}Users{_SEP}{_NAME}", re.I),
        "<home>",
        "user home directory",
    ),
    (
        re.compile(rf"[A-Za-z]:{_SEP}Xilinx{_SEP}Vivado{_SEP}[\d.]+", re.I),
        "<vivado>",
        "Vivado installation directory",
    ),
    (
        re.compile(rf"[A-Za-z]:{_SEP}{_NAME}{_SEP}oss-cad-suite", re.I),
        "<oss-cad-suite>",
        "OSS CAD Suite installation directory",
    ),
]
# drive-letter path: letter not preceded by another letter (excludes "https://", "TIMING:/..."), then
# a backslash or a single forward slash (a double slash is a URL scheme)
_RESIDUAL_PATH = re.compile(rf"(?<![A-Za-z])[A-Za-z]:(?:(?:\\\\|\\)|/(?!/)){_NAME}")


def redact_text(text: str) -> str:
    for pat, repl, _ in REDACTION_RULES:
        text = pat.sub(repl, text)
    return text


def redact(obj: Any) -> Any:
    """Recursively redact every string inside dicts / lists."""
    if isinstance(obj, str):
        return redact_text(obj)
    if isinstance(obj, list):
        return [redact(x) for x in obj]
    if isinstance(obj, dict):
        return {k: redact(v) for k, v in obj.items()}
    return obj


def residual_paths(text: str) -> list[str]:
    """Drive-letter paths still present after redaction (used for the manifest self-check)."""
    return _RESIDUAL_PATH.findall(text)


# --------------------------------------------------------------------------- #
# export
# --------------------------------------------------------------------------- #
VERDICT_COLUMNS = [
    "sample_id", "model", "model_version", "problem_id", "level", "spec_version", "strategy", "idx",
    "round", "stage", "passed", "sim_passed", "synth_ok", "synthesizable", "unintended_latch", "tool_disagreement",
    "needs_review", "primary_error", "errors", "lint_density", "n_failed_cases", "LUT", "FF", "Fmax_MHz",
]
SAMPLE_COLUMNS = [
    "sample_id", "model", "model_version", "problem_id", "level", "spec_version", "strategy", "idx",
    "temperature", "created_at", "n_rounds", "initial_stage", "initial_passed", "initial_synthesizable",
    "initial_unintended_latch", "initial_primary_error", "initial_needs_review", "initial_lint_density",
    "final_passed", "final_stage", "repaired", "final_LUT", "final_FF", "final_Fmax_MHz",
]


def _as_bool(x: Any) -> bool:
    if isinstance(x, str):
        return x.strip().lower() in ("1", "true", "yes")
    return bool(x)


@dataclass
class ExportStats:
    samples: int = 0
    verdicts: int = 0
    residual_paths: int = 0
    files: dict[str, int] | None = None


def _levels(benchmark_root: Path | None) -> dict[str, str]:
    """problem_id -> level, read from the benchmark directory layout (benchmark/L?/<id>)."""
    if benchmark_root is None:
        from .benchmark import find_benchmark_root

        try:
            benchmark_root = find_benchmark_root()
        except Exception:  # pragma: no cover - benchmark not available
            return {}
    out: dict[str, str] = {}
    for lvl in ("L1", "L2", "L3"):
        d = Path(benchmark_root) / lvl
        if d.is_dir():
            for p in d.iterdir():
                if p.is_dir():
                    out[p.name] = lvl
    return out


def _rows(store: ResultStore) -> Iterator[tuple[dict, list[dict]]]:
    """Yield (sample_row, [verdict_rows]) straight from SQLite (keeps ids, avoids re-parsing)."""
    conn = store.conn
    import sqlite3

    conn.row_factory = sqlite3.Row
    for s in conn.execute("SELECT * FROM samples ORDER BY id"):
        vs = [dict(v) for v in conn.execute("SELECT * FROM verdicts WHERE sample_id=? ORDER BY round", (s["id"],))]
        yield dict(s), vs


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def export_dataset(
    db_path: Path,
    out_dir: Path,
    *,
    benchmark_root: Path | None = None,
    redact_paths: bool = True,
    include_tool_logs: bool = True,
) -> ExportStats:
    db_path, out_dir = Path(db_path), Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    store = ResultStore(db_path)
    levels = _levels(benchmark_root)
    rd = redact if redact_paths else (lambda x: x)
    stats = ExportStats(files={})
    residual = 0

    f_samples = open(out_dir / "samples.jsonl", "w", encoding="utf-8", newline="\n")
    f_logs = open(out_dir / "tool_logs.jsonl", "w", encoding="utf-8", newline="\n") if include_tool_logs else None
    f_vcsv = open(out_dir / "verdicts.csv", "w", encoding="utf-8", newline="")
    f_scsv = open(out_dir / "samples.csv", "w", encoding="utf-8", newline="")
    w_v = csv.DictWriter(f_vcsv, fieldnames=VERDICT_COLUMNS)
    w_s = csv.DictWriter(f_scsv, fieldnames=SAMPLE_COLUMNS)
    w_v.writeheader()
    w_s.writeheader()
    try:
        for s, vs in _rows(store):
            sid = s["id"]
            base = {
                "sample_id": sid,
                "model": s["model"],
                "model_version": s["model_version"],
                "problem_id": s["problem_id"],
                "level": levels.get(s["problem_id"], ""),
                "spec_version": s["spec_version"],
                "strategy": s["strategy"],
                "idx": s["idx"],
            }
            rounds: list[dict] = []
            for v in vs:
                lint_counts = json.loads(v["lint_counts"] or "{}")
                failed = rd(json.loads(v["failed_cases"] or "[]"))
                res = json.loads(v["resources"] or "{}")
                logs = rd(json.loads(v["tool_logs"] or "{}"))
                needs_review = _as_bool(logs.get("needs_review", False)) if isinstance(logs, dict) else False
                # synthesis is only attempted once the code compiles; before that the stored flag is a
                # default and must not be read as "synthesizable"
                synth_attempted = v["stage"] not in ("interface", "compile")
                synth_ok: bool | None = bool(v["synth_ok"]) if synth_attempted else None
                synthesizable = bool(synth_attempted and synth_ok)
                rounds.append(
                    {
                        "round": v["round"],
                        "stage": v["stage"],
                        "passed": bool(v["passed"]),
                        "sim_passed": bool(v["sim_passed"]),
                        "synth_ok": synth_ok,
                        "synthesizable": synthesizable,
                        "unintended_latch": bool(v["unintended_latch"]),
                        "tool_disagreement": bool(v["tool_disagreement"]),
                        "needs_review": needs_review,
                        "primary_error": v["primary_error"],
                        "errors": json.loads(v["errors"] or "[]"),
                        "lint_density": v["lint_density"],
                        "lint_counts": lint_counts,
                        "failed_cases": failed,
                        "resources": res,
                        # per-round code / reply (null for databases written before this field existed)
                        "code": v.get("code"),
                        "raw_response": v.get("raw_response"),
                    }
                )
                w_v.writerow(
                    {
                        **base,
                        "round": v["round"],
                        "stage": v["stage"],
                        "passed": int(v["passed"]),
                        "sim_passed": int(v["sim_passed"]),
                        "synth_ok": "" if synth_ok is None else int(synth_ok),
                        "synthesizable": int(synthesizable),
                        "unintended_latch": int(v["unintended_latch"]),
                        "tool_disagreement": int(v["tool_disagreement"] or 0),
                        "needs_review": int(needs_review),
                        "primary_error": v["primary_error"] or "",
                        "errors": ";".join(json.loads(v["errors"] or "[]")),
                        "lint_density": v["lint_density"] if v["lint_density"] is not None else "",
                        "n_failed_cases": len(failed),
                        "LUT": res.get("LUT", ""),
                        "FF": res.get("FF", ""),
                        "Fmax_MHz": res.get("Fmax_MHz", ""),
                    }
                )
                if f_logs is not None:
                    line = json.dumps({"sample_id": sid, "round": v["round"], **{k: logs.get(k, "") for k in ("compile", "sim", "synth", "rationale")}}, ensure_ascii=False)
                    residual += len(residual_paths(line))
                    f_logs.write(line + "\n")
                stats.verdicts += 1

            record = {
                **base,
                "temperature": s["temperature"],
                "created_at": s["created_at"],
                "prompt": s["prompt"],
                "raw_response": s["raw_response"],
                "code": s["code"],
                "rounds": rounds,
            }
            line = json.dumps(record, ensure_ascii=False)
            residual += len(residual_paths(line))
            f_samples.write(line + "\n")

            first, last = rounds[0] if rounds else None, rounds[-1] if rounds else None
            w_s.writerow(
                {
                    **base,
                    "temperature": s["temperature"],
                    "created_at": s["created_at"],
                    "n_rounds": len(rounds),
                    "initial_stage": first["stage"] if first else "",
                    "initial_passed": int(first["passed"]) if first else "",
                    "initial_synthesizable": int(first["synthesizable"]) if first else "",
                    "initial_unintended_latch": int(first["unintended_latch"]) if first else "",
                    "initial_primary_error": (first["primary_error"] or "") if first else "",
                    "initial_needs_review": int(first["needs_review"]) if first else "",
                    "initial_lint_density": first["lint_density"] if first and first["lint_density"] is not None else "",
                    "final_passed": int(last["passed"]) if last else "",
                    "final_stage": last["stage"] if last else "",
                    "repaired": int(bool(last and last["passed"] and len(rounds) > 1)),
                    "final_LUT": last["resources"].get("LUT", "") if last else "",
                    "final_FF": last["resources"].get("FF", "") if last else "",
                    "final_Fmax_MHz": last["resources"].get("Fmax_MHz", "") if last else "",
                }
            )
            stats.samples += 1
    finally:
        f_samples.close()
        f_vcsv.close()
        f_scsv.close()
        if f_logs is not None:
            f_logs.close()

    stats.residual_paths = residual
    for p in out_dir.iterdir():
        if p.is_file() and p.name != "manifest.json":
            stats.files[p.name] = p.stat().st_size
    manifest = {
        "source_db": db_path.name,
        "source_db_sha256": _sha256(db_path),
        "samples": stats.samples,
        "verdicts": stats.verdicts,
        "models": [list(r) for r in store.conn.execute("SELECT DISTINCT model, model_version FROM samples ORDER BY model")],
        "redaction": [{"placeholder": repl, "meaning": desc} for _, repl, desc in REDACTION_RULES] if redact_paths else [],
        "residual_local_paths": residual,
        "files": stats.files,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return stats
