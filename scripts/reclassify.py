"""Re-apply the current taxonomy classifier (vleval/taxonomy.py) to the simulation-stage verdicts
already stored in a results database, without re-simulating anything.

    python scripts/reclassify.py results/results.db

Use it after a classification rule changes so that stored primary errors stay consistent with
the platform.  Evidence is rebuilt from the stored failed_cases tags, lint counts and latch flag.
History: applied once to the 2026-10 paper data when the rule "untagged comparison failure on an
FSM / system-level problem -> E7" (Table 3) was added; the DB is modified in place, back it up first.
"""

import json
import re
import sqlite3
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from vleval.benchmark import Benchmark  # noqa: E402
from vleval.models import Stage  # noqa: E402
from vleval.taxonomy import Evidence, classify  # noqa: E402

db = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / "results" / "results.db")
bench = Benchmark(ROOT / "benchmark")
c = sqlite3.connect(db)
rows = c.execute(
    """select v.sample_id, v.round, s.problem_id, v.failed_cases, v.lint_counts, v.unintended_latch, v.primary_error, v.errors, v.tool_logs
       from verdicts v join samples s on s.id=v.sample_id where v.stage='simulation'"""
).fetchall()
changed = Counter()
with c:
    for sid, rnd, pid, fc, lc, latch, prim, errs, logs in rows:
        p = bench.get(pid)
        tags = []
        for f in json.loads(fc or "[]"):
            m = re.search(r"tag=(\w+)", f)
            if m:
                tags.append(m.group(1))
        ev = Evidence(interface_ok=True, compile_ok=True, sim_ok=False, failed_tags=tags, lint_counts=json.loads(lc or "{}"),
                      unintended_latch=bool(latch), problem_level=p.level, problem_tags=p.tags)
        cls = classify(ev)
        assert cls.stage == Stage.SIMULATION
        new_prim = cls.primary.value if cls.primary else None
        new_errs = json.dumps([e.value for e in cls.errors])
        if new_prim != prim or new_errs != errs:
            changed[(prim, new_prim)] += 1
            tl = json.loads(logs or "{}")
            tl["rationale"] = "; ".join(cls.rationale)
            tl["needs_review"] = str(cls.needs_review)
            c.execute("update verdicts set primary_error=?, errors=?, tool_logs=? where sample_id=? and round=?",
                      (new_prim, new_errs, json.dumps(tl, ensure_ascii=False), sid, rnd))
print("simulation-stage verdicts:", len(rows), "changed:", sum(changed.values()))
for k, v in changed.most_common():
    print("  ", k, v)
