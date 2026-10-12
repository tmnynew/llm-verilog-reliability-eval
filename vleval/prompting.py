"""Prompt construction: spec version × strategy → chat messages (paper §2.3 ①, §3.3).

Templates live in ``vleval/templates`` and can be overridden by a directory
passed to :class:`PromptBuilder` so that teachers can tune wording without
touching code.  Placeholders use ``$name`` (``string.Template``) to avoid
clashing with Verilog braces.
"""

from __future__ import annotations

from pathlib import Path
from string import Template

from .models import Problem, SpecVersion, Strategy

Message = dict[str, str]  # {"role": ..., "content": ...}

_DEFAULT_DIR = Path(__file__).parent / "templates"

_TEMPLATE_FILES = {
    "system": "system.md",
    Strategy.ZERO_SHOT: "zero.md",
    Strategy.FEW_SHOT: "few.md",
    Strategy.CODING_CONSTRAINT: "constraint.md",
    Strategy.CHAIN_OF_THOUGHT: "cot.md",
    "repair": "repair.md",
}


class PromptBuilder:
    def __init__(self, template_dir: Path | None = None):
        self.dirs = [Path(template_dir)] if template_dir else []
        self.dirs.append(_DEFAULT_DIR)
        self._cache: dict[str, Template] = {}

    def _load(self, key) -> Template:
        name = _TEMPLATE_FILES[key]
        if name not in self._cache:
            for d in self.dirs:
                p = d / name
                if p.exists():
                    self._cache[name] = Template(p.read_text(encoding="utf-8"))
                    break
            else:
                raise FileNotFoundError(f"prompt template {name} not found in {self.dirs}")
        return self._cache[name]

    def _fewshot_block(self) -> str:
        for d in self.dirs:
            ex = d / "fewshot_examples.md"
            if ex.exists():
                return ex.read_text(encoding="utf-8")
        return ""

    # ------------------------------------------------------------------ #
    def build(self, problem: Problem, spec: SpecVersion, strategy: Strategy) -> list[Message]:
        vars_ = {
            "spec": problem.spec(spec).strip(),
            "interface": problem.interface.to_verilog_header(),
            "module": problem.interface.module,
            "examples": self._fewshot_block() if strategy == Strategy.FEW_SHOT else "",
        }
        system = self._load("system").safe_substitute(vars_)
        user = self._load(strategy).safe_substitute(vars_)
        return [{"role": "system", "content": system}, {"role": "user", "content": user}]

    def build_repair(self, problem: Problem, previous_code: str, feedback: str) -> Message:
        """Follow-up user turn appended to the original conversation (§2.3 ⑥)."""
        content = self._load("repair").safe_substitute(
            module=problem.interface.module,
            interface=problem.interface.to_verilog_header(),
            code=previous_code.strip(),
            feedback=feedback.strip(),
        )
        return {"role": "user", "content": content}


def flatten(messages: list[Message]) -> str:
    """Render messages as one string for logging / hashing."""
    return "\n\n".join(f"[{m['role']}]\n{m['content']}" for m in messages)
