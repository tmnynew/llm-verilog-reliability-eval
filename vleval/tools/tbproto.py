"""Testbench output protocol.

Every testbench in the benchmark prints:

* ``TB_FAIL tag=<tag> case=<id> exp=<value> got=<value>`` – one per failed check
  (``tag`` ∈ func, reset, width, state, timing, proto, handshake), at most
  ``MAX_REPORT`` lines to keep logs small;
* exactly one terminating line
  ``TB_RESULT PASS n_checks=<N>`` or ``TB_RESULT FAIL n_fail=<M> n_checks=<N>``.

A missing ``TB_RESULT`` line (crash, ``$finish`` never reached, timeout) is a
failure with tag ``crash``.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

_FAIL_RE = re.compile(r"^TB_FAIL\s+tag=(\w+)(.*)$", re.M)
_RESULT_RE = re.compile(r"^TB_RESULT\s+(PASS|FAIL)(?:\s+n_fail=(\d+))?\s+n_checks=(\d+)", re.M)


@dataclass
class TbOutcome:
    passed: bool
    n_checks: int = 0
    n_fail: int = 0
    fail_lines: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)
    crashed: bool = False


def parse_tb_output(stdout: str, timed_out: bool = False) -> TbOutcome:
    fails = _FAIL_RE.findall(stdout)
    lines = [ln for ln in stdout.splitlines() if ln.startswith("TB_FAIL")]
    tags: list[str] = []
    for tag, _ in fails:
        if tag not in tags:
            tags.append(tag)
    m = _RESULT_RE.search(stdout)
    if timed_out or not m:
        return TbOutcome(False, 0, len(lines), lines[:20], tags + ["crash"], crashed=True)
    status, n_fail, n_checks = m.groups()
    return TbOutcome(status == "PASS", int(n_checks), int(n_fail or 0), lines[:20], tags)
