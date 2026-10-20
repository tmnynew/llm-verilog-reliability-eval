"""Mutation testing for testbench validation (paper §2.2).

Generates *first-order* mutants of a golden model with the operator families
listed in the paper and computes the mutation score of the testbench.

Operators (``op`` field in ``mutants/index.json``)::

    ROR   relational operator replacement    ==  !=  <  <=  >  >=
    AOR   arithmetic operator replacement    +  <->  -
    LOR   logical/bitwise operator replacement  && <-> ||,  & <-> |,  ^ -> |
    URO   unary reduction/bitwise-not replacement  ^x -> |x,  ~x -> x
    UOI   condition negation                 if (c) -> if (!(c))
    RST   reset polarity flip                !rst_n -> rst_n, if (rst) -> if (!rst)
    CRP   constant replacement               1'b0 <-> 1'b1, 3'd7 -> 3'd6, 7'b100_0000 -> 7'b100_0001, N -> N+1
    WID   internal width change              reg [7:0] -> reg [6:0] / [8:0]
    DDL   default branch deletion
    BSR   blocking / non-blocking swap inside always blocks
    SDL   statement deletion (a single assignment)

A tiny tokenizer is used instead of a full parser: mutants only have to be
*plausible*, and stillborn mutants (that no longer compile) are detected and
excluded when the score is computed.
"""

from __future__ import annotations

import json
import random
import re
from collections.abc import Callable
from dataclasses import asdict, dataclass
from pathlib import Path

from .models import Problem

# --------------------------------------------------------------------------- #
# Tokenizer
# --------------------------------------------------------------------------- #
_TOKEN_RE = re.compile(
    r"""
    (?P<comment>//[^\n]*|/\*.*?\*/)
  | (?P<string>"(?:\\.|[^"\\])*")
  | (?P<number>\d*\s*'[sS]?[bBhHdDoO]\s*[0-9a-fA-FxXzZ_?]+|\d[\d_]*(?:\.\d+)?)
  | (?P<ident>[A-Za-z_$][\w$]*|\\\S+)
  | (?P<op><<<|>>>|<=|>=|==|!=|===|!==|&&|\|\||<<|>>|\*\*|[-+*/%<>!~&|^=?:;,.()\[\]{}#@])
  | (?P<ws>\s+)
    """,
    re.S | re.X,
)

KEYWORDS = {
    "if",
    "else",
    "case",
    "casez",
    "casex",
    "default",
    "begin",
    "end",
    "always",
    "assign",
    "for",
    "while",
    "endcase",
    "module",
    "endmodule",
    "input",
    "output",
    "reg",
    "wire",
    "parameter",
    "localparam",
    "integer",
    "posedge",
    "negedge",
    "or",
    "endfunction",
    "function",
}


@dataclass
class Tok:
    kind: str
    text: str
    start: int
    end: int
    depth_paren: int = 0
    depth_bracket: int = 0
    in_always: bool = False
    in_seq_always: bool = False  # sensitivity list contains posedge/negedge
    in_port_decl: bool = False
    in_param_decl: bool = False  # parameter / localparam declaration (mutating these is almost always equivalent)
    in_for_header: bool = False  # `for ( ... )` control part: mutants there usually never terminate


def tokenize(code: str) -> list[Tok]:
    toks: list[Tok] = []
    paren = bracket = 0
    in_always = False
    seq_always = False
    always_begin_depth = 0  # begin/end nesting inside current always
    pending_always = False
    port_decl = False
    param_decl = False
    for_pending = False  # saw `for`, waiting for its `(`
    for_paren = -1  # paren depth at which the current for-header opened (-1: not in one)
    for m in _TOKEN_RE.finditer(code):
        kind = m.lastgroup
        text = m.group()
        if kind in ("ws", "comment"):
            continue
        if kind == "ident" and text in ("parameter", "localparam"):
            param_decl = True
        if kind == "ident" and text == "for":
            for_pending = True
        if for_pending and kind == "op" and text == "(":
            for_pending, for_paren = False, paren
        t = Tok(kind, text, m.start(), m.end(), paren, bracket, in_always, in_always and seq_always, port_decl, param_decl, for_paren >= 0)
        toks.append(t)
        if for_paren >= 0 and kind == "op" and text == ")" and paren - 1 == for_paren:
            for_paren = -1
        if param_decl and ((kind == "op" and text == ";") or (kind == "ident" and text in ("input", "output", "inout", "wire", "reg", "always", "assign"))):
            # end of `parameter X = v;` – a following `parameter` re-arms it.  Commas do not end the
            # declaration (`parameter A = 1, B = 2`); inside `#( ... )` it ends with the closing paren.
            param_decl = False
        if kind == "op":
            if text == "(":
                paren += 1
            elif text == ")":
                paren = max(0, paren - 1)
                if param_decl and paren == 0:
                    param_decl = False
            elif text == "[":
                bracket += 1
            elif text == "]":
                bracket = max(0, bracket - 1)
            elif text == ";" and in_always and always_begin_depth == 0 and not pending_always:
                in_always = False
        elif kind == "ident":
            if text == "always":
                in_always, pending_always, always_begin_depth, seq_always = True, True, 0, False
            elif text in ("posedge", "negedge") and pending_always:
                seq_always = True
            elif text in ("input", "output", "inout"):
                port_decl = True
            elif text == "begin" and in_always:
                always_begin_depth += 1
                pending_always = False
            elif text == "end" and in_always:
                always_begin_depth -= 1
                if always_begin_depth <= 0:
                    in_always = False
            elif in_always and pending_always and text not in ("@", "always"):
                # first statement token after the sensitivity list
                if paren == 0:
                    pending_always = False
        if kind == "op" and text in (";", ")") and port_decl and paren == 0:
            port_decl = False
    return toks


_SIZED_RE = re.compile(r"^(\d+)\s*'([sS]?)([bBhHdDoO])\s*([0-9a-fA-F_]+)$")


def _mutate_sized_constant(text: str) -> str | None:
    """Return a neighbouring value of a sized literal (``3'd7`` → ``3'd6``, ``7'b100_0000`` → ``7'b100_0001``)."""
    m = _SIZED_RE.match(text.replace(" ", ""))
    if not m:
        return None
    width, sign, base, digits = m.groups()
    radix = {"b": 2, "h": 16, "d": 10, "o": 8}[base.lower()]
    try:
        value = int(digits.replace("_", ""), radix)
    except ValueError:
        return None
    new_value = value ^ 1 if radix != 10 else (value + 1 if value + 1 < 2 ** int(width) else value - 1)
    if new_value == value or new_value < 0:
        return None
    fmt = {2: "b", 16: "x", 10: "d", 8: "o"}[radix]
    return f"{width}'{sign}{base}{format(new_value, fmt)}"


# --------------------------------------------------------------------------- #
# Mutants
# --------------------------------------------------------------------------- #
@dataclass
class Mutant:
    id: str
    op: str
    line: int
    original: str
    replacement: str
    description: str
    code: str = ""

    def meta(self) -> dict:
        d = asdict(self)
        d.pop("code")
        return d


Candidate = tuple[str, int, int, str, str]  # op, start, end, original_text, replacement_text


def _is_operand(t: Tok | None) -> bool:
    return t is not None and (t.kind in ("ident", "number") or t.text in (")", "]"))


def _line_of(code: str, pos: int) -> int:
    return code.count("\n", 0, pos) + 1


def _read_later_in_block(toks: list[Tok], assign_idx: int, name: str) -> bool:
    """True if *name* is read (appears on a right-hand side / condition) after the
    assignment at *assign_idx* and before the enclosing always block ends."""
    j = assign_idx + 1
    while j < len(toks) and toks[j].text != ";":  # skip this statement's RHS
        j += 1
    j += 1
    # The statement is the whole body of an if/case arm when it is directly followed by
    # `else`, a case label (`x:` / `default:`) or `endcase`: what follows is an alternative
    # branch, not a later statement.
    if j < len(toks) and (toks[j].text in ("else", "default", "endcase") or (j + 1 < len(toks) and toks[j + 1].text == ":")):
        return False
    depth = 0  # begin/end depth relative to the assignment; leaving its block ends the search
    while j < len(toks) and toks[j].in_always and depth >= 0:
        t = toks[j]
        if t.text == "begin":
            depth += 1
        elif t.text == "end":
            depth -= 1
        elif t.kind == "ident" and t.text == name:
            nxt = toks[j + 1] if j + 1 < len(toks) else None
            # `name <= …` / `name = …` / `name[i] <= …` is a write, anything else is a read
            is_write = nxt is not None and (nxt.text in ("<=", "=") or (nxt.text == "[" and _closing_bracket_then_assign(toks, j + 1)))
            if not is_write:
                return True
        j += 1
    return False


def _closing_bracket_then_assign(toks: list[Tok], open_idx: int) -> bool:
    depth = 0
    for k in range(open_idx, len(toks)):
        if toks[k].text == "[":
            depth += 1
        elif toks[k].text == "]":
            depth -= 1
            if depth == 0:
                return k + 1 < len(toks) and toks[k + 1].text in ("<=", "=")
    return False


def _candidates(code: str) -> list[Candidate]:
    toks = tokenize(code)
    cands: list[Candidate] = []
    rel_alt = {"==": "!=", "!=": "==", "<": "<=", "<=": "<", ">": ">=", ">=": ">"}
    log_alt = {"&&": "||", "||": "&&", "&": "|", "|": "&"}

    for i, t in enumerate(toks):
        prev = toks[i - 1] if i else None
        nxt = toks[i + 1] if i + 1 < len(toks) else None
        if t.in_param_decl:
            continue  # parameter defaults / derived widths: mutants there are equivalent for the testbench
        if t.in_for_header:
            continue  # `for (k = 0; k < N; k = k + 1)`: `k - 1` / `k >= N` never terminate and can hang the tools
        if t.kind == "op":
            is_nonblocking = t.text == "<=" and t.in_always and t.depth_paren == 0
            # ROR
            if t.text in rel_alt and not is_nonblocking and not (t.text in ("<", ">") and t.depth_bracket):
                cands.append(("ROR", t.start, t.end, t.text, rel_alt[t.text]))
            # AOR (binary only, not inside [] ranges)
            if t.text in ("+", "-") and _is_operand(prev) and _is_operand(nxt) and t.depth_bracket == 0:
                cands.append(("AOR", t.start, t.end, t.text, "-" if t.text == "+" else "+"))
            # LOR (binary only – previous token must be an operand, else it is a reduction op)
            if t.text in log_alt and _is_operand(prev) and (nxt is None or nxt.text not in ("&", "|")):
                cands.append(("LOR", t.start, t.end, t.text, log_alt[t.text]))
            if t.text == "^" and _is_operand(prev) and _is_operand(nxt):
                cands.append(("LOR", t.start, t.end, "^", "|"))
            # URO – unary reduction / bitwise-not replacement: ^x → |x, ~x → x, |x → &x
            if t.text in ("^", "|", "&", "~") and not _is_operand(prev) and nxt is not None and (nxt.kind == "ident" or nxt.text == "("):
                repl = {"^": "|", "|": "&", "&": "|", "~": ""}[t.text]
                cands.append(("URO", t.start, t.end, t.text, repl))
            # BSR – swap assignment kinds inside *clocked* always blocks (in combinational
            # blocks the swap is almost always an equivalent mutant).  `<=` → `=` only changes
            # behaviour when the target is read again later in the same block, so require that.
            if is_nonblocking and t.in_seq_always and prev is not None and prev.kind == "ident" and _read_later_in_block(toks, i, prev.text):
                cands.append(("BSR", t.start, t.end, "<=", "="))
            elif (
                t.text == "="
                and t.in_seq_always
                and t.depth_paren == 0
                and prev is not None
                and prev.text not in ("<", ">", "!", "=")
                and not (nxt and nxt.text == "=")
            ):
                cands.append(("BSR", t.start, t.end, "=", "<="))
            # RST via negation removal: !rst / ~rst
            if t.text in ("!", "~") and nxt is not None and nxt.kind == "ident" and re.search(r"rst|reset", nxt.text, re.I):
                cands.append(("RST", t.start, t.end, t.text, ""))
        elif t.kind == "number":
            txt = t.text.replace(" ", "")
            if re.fullmatch(r"1'[bB][01]", txt):
                cands.append(("CRP", t.start, t.end, t.text, txt[:-1] + ("0" if txt.endswith("1") else "1")))
            elif "'" in txt and not t.in_port_decl and t.depth_bracket == 0:
                repl = _mutate_sized_constant(txt)
                if repl:
                    cands.append(("CRP", t.start, t.end, t.text, repl))
            elif (
                re.fullmatch(r"\d+", txt)
                and t.depth_bracket == 0
                and not t.in_port_decl
                and prev is not None
                and prev.text in ("==", "!=", "<", ">", "<=", ">=", "=", "-", "+")
            ):
                cands.append(("CRP", t.start, t.end, t.text, str(int(txt) + 1)))
            elif re.fullmatch(r"\d+", txt) and t.depth_bracket > 0 and not t.in_port_decl and nxt is not None and nxt.text == ":":
                # WID: narrow an internal range by one bit (widening is almost always equivalent)
                if prev is not None and prev.text == "[" and int(txt) > 0:  # [7:0] → [6:0]
                    cands.append(("WID", t.start, t.end, t.text, str(int(txt) - 1)))
                elif prev is not None and prev.text == "-" and i >= 3 and toks[i - 3].text == "[":  # [W-1:0] → [W-2:0]
                    cands.append(("WID", t.start, t.end, t.text, str(int(txt) + 1)))
        elif t.kind == "ident":
            # RST: un-negated reset in an if condition → negate it
            if (
                re.search(r"rst|reset", t.text, re.I)
                and prev is not None
                and prev.text == "("
                and i >= 2
                and toks[i - 2].text == "if"
                and nxt is not None
                and nxt.text == ")"
            ):
                cands.append(("RST", t.start, t.end, t.text, "!" + t.text))
            # UOI: negate whole if-condition
            if t.text == "if" and nxt is not None and nxt.text == "(":
                depth, j = 0, i + 1
                while j < len(toks):
                    if toks[j].text == "(":
                        depth += 1
                    elif toks[j].text == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                if j < len(toks):
                    inner = code[toks[i + 1].end : toks[j].start]
                    cands.append(("UOI", toks[i + 1].start, toks[j].end, f"({inner})", f"(!({inner}))"))
            # DDL: delete default branch
            if t.text == "default" and nxt is not None and nxt.text == ":":
                j = i + 2
                if j < len(toks) and toks[j].text == "begin":
                    depth = 0
                    while j < len(toks):
                        if toks[j].text == "begin":
                            depth += 1
                        elif toks[j].text == "end":
                            depth -= 1
                            if depth == 0:
                                break
                        j += 1
                else:
                    while j < len(toks) and toks[j].text != ";":
                        j += 1
                if j < len(toks):
                    seg = code[t.start : toks[j].end]
                    cands.append(("DDL", t.start, toks[j].end, seg, "/* default removed */"))
            # SDL: delete a simple statement `x <= expr;` inside always (not the only one in a block)
            if (
                t.in_always
                and t.depth_paren == 0
                and nxt is not None
                and nxt.text in ("<=", "=")
                and prev is not None
                and prev.text in (";", "begin", ")", "else")
            ):
                j = i
                while j < len(toks) and toks[j].text != ";":
                    j += 1
                if j < len(toks) and prev.text in (";", "begin"):
                    seg = code[t.start : toks[j].end]
                    cands.append(("SDL", t.start, toks[j].end, seg, "/* statement removed */"))
    # remove duplicates, keep deterministic order
    seen = set()
    uniq = []
    for c in cands:
        if c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq


def generate_mutants(code: str, n: int = 20, seed: int = 1) -> list[Mutant]:
    """Pick up to *n* mutants, round-robin over operator families for diversity."""
    cands = _candidates(code)
    rng = random.Random(seed)
    by_op: dict[str, list[Candidate]] = {}
    for c in cands:
        by_op.setdefault(c[0], []).append(c)
    for lst in by_op.values():
        rng.shuffle(lst)
    chosen: list[Candidate] = []
    ops = sorted(by_op)
    while len(chosen) < n and any(by_op.values()):
        for op in ops:
            if by_op[op] and len(chosen) < n:
                chosen.append(by_op[op].pop())
    chosen.sort(key=lambda c: c[1])
    mutants = []
    for k, (op, s, e, orig, repl) in enumerate(chosen, 1):
        mid = f"m{k:03d}"
        line = _line_of(code, s)
        desc = f"{op} line {line}: {orig.strip()[:40]!r} -> {repl.strip()[:40]!r}"
        header = f"// MUTANT {mid} {desc}\n"
        mutants.append(Mutant(mid, op, line, orig, repl, desc, header + code[:s] + repl + code[e:]))
    return mutants


def write_mutants(problem: Problem, mutants: list[Mutant]) -> Path:
    d = problem.mutants_dir
    d.mkdir(exist_ok=True)
    for old in d.glob("m*.v"):
        old.unlink()
    for m in mutants:
        (d / f"{m.id}.v").write_text(m.code, encoding="utf-8")
    (d / "index.json").write_text(json.dumps([m.meta() for m in mutants], ensure_ascii=False, indent=2), encoding="utf-8")
    return d


def load_equivalent(problem: Problem) -> set:
    p = problem.root / "equivalent.txt"
    if not p.exists():
        return set()
    return {ln.split()[0] for ln in p.read_text(encoding="utf-8").splitlines() if ln.strip() and not ln.startswith("#")}


@dataclass
class MutationScore:
    problem_id: str
    total: int
    killed: int
    survived: list[str]
    stillborn: list[str]
    equivalent: list[str]

    @property
    def score(self) -> float:
        denom = self.total - len(self.stillborn) - len(self.equivalent)
        return self.killed / denom if denom else 0.0


def mutation_score(problem: Problem, run_sim: Callable[[Path], tuple[bool, bool]], threshold: float = 0.95) -> MutationScore:
    """Compute the mutation score.

    *run_sim(path)* must return ``(compiled, sim_passed)`` for a DUT file.
    A mutant is *killed* when it compiles and the testbench fails.
    """
    index = json.loads((problem.mutants_dir / "index.json").read_text(encoding="utf-8"))
    equivalent = load_equivalent(problem)
    killed, survived, stillborn = 0, [], []
    for meta in index:
        mid = meta["id"]
        if mid in equivalent:
            continue
        compiled, passed = run_sim(problem.mutants_dir / f"{mid}.v")
        if not compiled:
            stillborn.append(mid)
        elif passed:
            survived.append(mid)
        else:
            killed += 1
    return MutationScore(problem.id, len(index), killed, survived, stillborn, sorted(equivalent))
