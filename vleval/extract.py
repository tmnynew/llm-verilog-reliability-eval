"""Code extraction and lightweight static analysis of LLM output.

The functions here are intentionally regex based: they only need to be robust
enough for (a) pulling the Verilog module out of a chat response and (b) the
interface check, which is the first judging stage.  Anything deeper is left
to the real EDA tools.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .models import Interface, Port

_FENCE_RE = re.compile(r"```(?:[a-zA-Z0-9_+-]*)\s*\n(.*?)```", re.S)
_COMMENT_BLOCK_RE = re.compile(r"/\*.*?\*/", re.S)
_COMMENT_LINE_RE = re.compile(r"//[^\n]*")
_MODULE_RE = re.compile(r"\bmodule\s+([A-Za-z_][\w$]*)\s*(#\s*\((.*?)\))?\s*\((.*?)\)\s*;", re.S)
_PORT_DECL_RE = re.compile(r"\b(input|output|inout)\b\s*(?:(wire|reg|logic)\s+)?(?:signed\s+)?(?:\[\s*([^\]:]+)\s*:\s*([^\]]+)\s*\])?\s*([A-Za-z_][\w$]*)")
_PARAM_RE = re.compile(r"\bparameter\b(?:\s+\w+)?\s+([A-Za-z_]\w*)\s*=\s*([^,;)]+)")
# `parameter A = 1, B = 2, C = 3` – further assignments after the first one
_PARAM_CONT_RE = re.compile(r"\s*,\s*([A-Za-z_]\w*)\s*=\s*([^,;)]+)")


def extract_code(response: str) -> str:
    """Return the Verilog source contained in an LLM response.

    Preference order: the longest fenced block containing ``module`` →
    the raw text if it already contains ``module`` … ``endmodule``.
    """
    blocks = [b for b in _FENCE_RE.findall(response) if "module" in b]
    if blocks:
        return max(blocks, key=len).strip() + "\n"
    if "endmodule" in response:
        start = response.find("module")
        # jump back to a preceding `timescale / comment if present
        return response[start:].strip() + "\n"
    return response.strip() + "\n"


def strip_comments(code: str) -> str:
    return _COMMENT_LINE_RE.sub("", _COMMENT_BLOCK_RE.sub("", code))


def effective_lines(code: str) -> int:
    """Non-blank, non-comment lines – the denominator of lint density."""
    return sum(1 for ln in strip_comments(code).splitlines() if ln.strip())


def _eval_width(msb: str, lsb: str, params: dict[str, int]) -> int | None:
    """Evaluate ``[msb:lsb]`` with simple constant folding; None if unknown."""
    env = {k: int(v) for k, v in params.items()}

    def ev(expr: str) -> int | None:
        expr = expr.strip()
        if not re.fullmatch(r"[\w\s+\-*/()$clog2]+", expr):
            return None
        expr = re.sub(r"\$clog2\(([^)]+)\)", lambda m: f"__clog2({m.group(1)})", expr)
        env["__clog2"] = lambda n: (int(n) - 1).bit_length()  # type: ignore[assignment]
        try:
            return int(eval(expr, {"__builtins__": {}}, env))  # noqa: S307 – constant expr only
        except Exception:
            return None

    a, b = ev(msb), ev(lsb)
    if a is None or b is None:
        return None
    return abs(a - b) + 1


@dataclass
class ParsedModule:
    name: str
    ports: list[Port]
    parameters: dict[str, str] = field(default_factory=dict)
    unknown_width_ports: list[str] = field(default_factory=list)


def parse_module(code: str, default_params: dict[str, int] | None = None) -> ParsedModule | None:
    """Parse the first module header (ANSI or non-ANSI port style)."""
    clean = strip_comments(code)
    m = _MODULE_RE.search(clean)
    if not m:
        return None
    name, _, param_blob, port_blob = m.groups()
    params: dict[str, str] = {}
    for src in (param_blob or "", clean[m.end() :]):
        for pm in _PARAM_RE.finditer(src):
            params.setdefault(pm.group(1), pm.group(2).strip())
            pos = pm.end()
            while (cm := _PARAM_CONT_RE.match(src, pos)) is not None:
                params.setdefault(cm.group(1), cm.group(2).strip())
                pos = cm.end()
    numeric: dict[str, int] = dict(default_params or {})
    for k, v in params.items():
        try:
            numeric.setdefault(k, int(v))
        except ValueError:
            pass

    ports: list[Port] = []
    unknown: list[str] = []
    # ANSI style: declarations inside the port list; non-ANSI: inside body.
    search_space = port_blob if _PORT_DECL_RE.search(port_blob) else clean[m.end() :]
    seen = set()
    for pm in _PORT_DECL_RE.finditer(search_space):
        direction, _, msb, lsb, pname = pm.groups()
        if pname in seen:
            continue
        seen.add(pname)
        width = 1
        if msb is not None:
            w = _eval_width(msb, lsb, numeric)
            if w is None:
                unknown.append(pname)
                w = 1
            width = w
        ports.append(Port(pname, "output" if direction == "output" else "input", width))
    return ParsedModule(name=name, ports=ports, parameters=params, unknown_width_ports=unknown)


def check_interface(code: str, expected: Interface) -> tuple[bool, list[str]]:
    """Stage-1 check: module name, port names, directions and widths must match."""
    parsed = parse_module(code, expected.parameters)
    if parsed is None:
        return False, ["no module definition found"]
    issues: list[str] = []
    if parsed.name != expected.module:
        issues.append(f"module name {parsed.name!r} != {expected.module!r}")
    for pname in expected.parameters:
        if pname not in parsed.parameters:
            issues.append(f"missing parameter {pname}")
    exp = expected.port_map()
    got = {p.name: p for p in parsed.ports}
    for name in exp.keys() - got.keys():
        issues.append(f"missing port {name}")
    for name in got.keys() - exp.keys():
        issues.append(f"unexpected port {name}")
    for name in exp.keys() & got.keys():
        e, g = exp[name], got[name]
        if e.direction != g.direction:
            issues.append(f"port {name}: direction {g.direction} != {e.direction}")
        if name not in parsed.unknown_width_ports and e.width != g.width:
            issues.append(f"port {name}: width {g.width} != {e.width}")
    return not issues, issues


# --------------------------------------------------------------------------- #
# Static hints for the taxonomy (complement tool output, never replace it)
# --------------------------------------------------------------------------- #
SIM_ONLY_PATTERNS: dict[str, str] = {
    "initial": r"\binitial\b",
    "delay": r"#\s*\d",
    "display": r"\$(display|monitor|write|strobe|finish|stop|time|random|urandom)\b",
    "event": r"\bwait\s*\(|@\s*\(\s*(posedge|negedge)[^)]*\)\s*;",  # bare event control as a statement
    "force": r"\b(force|release|fork|join)\b",
}
SV_ONLY_PATTERNS: dict[str, str] = {
    "logic": r"\blogic\b",
    "always_ff": r"\balways_(ff|comb|latch)\b",
    "typedef": r"\b(typedef|enum|struct|interface|package|import)\b",
    "unique": r"\b(unique|priority)\s+(case|if)\b",
    "inside": r"\binside\b",
    "incdec": r"\+\+|--(?!-)",
    "assign_op": r"[+\-*/&|^]=(?!=)",
}


def find_patterns(code: str, patterns: dict[str, str]) -> dict[str, int]:
    clean = strip_comments(code)
    hits: dict[str, int] = {}
    for key, pat in patterns.items():
        n = len(re.findall(pat, clean, flags=re.M))
        if n:
            hits[key] = n
    return hits


def sim_only_constructs(code: str) -> dict[str, int]:
    """E9 hint: constructs that simulate but are ignored / rejected by synthesis."""
    return find_patterns(code, SIM_ONLY_PATTERNS)


def systemverilog_constructs(code: str) -> dict[str, int]:
    """E2 hint: SystemVerilog-only syntax (course restricts to Verilog-2001)."""
    return find_patterns(code, SV_ONLY_PATTERNS)
