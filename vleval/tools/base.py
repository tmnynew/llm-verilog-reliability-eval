"""Common subprocess plumbing for EDA tool wrappers."""

from __future__ import annotations

import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

from ..models import ToolResult


@dataclass
class ToolConfig:
    verilator: str = "verilator"
    verilator_coverage: str = "verilator_coverage"
    iverilog: str = "iverilog"
    vvp: str = "vvp"
    yosys: str = "yosys"
    vivado: str = "vivado"
    simulator: str = "auto"  # verilator | iverilog | auto
    linter: str = "auto"  # verilator | iverilog | auto  (Verilog-2001 compile check + lint)
    sim_timeout_s: int = 60  # paper §2.3 ④
    compile_timeout_s: int = 120
    synth_timeout_s: int = 600
    fpga_part: str = "xc7a35tcpg236-1"  # Basys3
    clock_period_ns: float = 5.0  # 200 MHz tight constraint (paper §1.2)
    enable_vivado: bool = False
    enable_yosys: bool = True
    extra: dict[str, str] = field(default_factory=dict)

    @staticmethod
    def from_yaml(path: Path) -> ToolConfig:
        import yaml

        data = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
        return ToolConfig(**{k: v for k, v in data.items() if k in ToolConfig.__dataclass_fields__})

    def pick_simulator(self) -> str:
        if self.simulator != "auto":
            return self.simulator
        if shutil.which(self.verilator):
            return "verilator"
        if shutil.which(self.iverilog):
            return "iverilog"
        raise RuntimeError("no simulator found (verilator / iverilog)")

    def pick_linter(self) -> str:
        if self.linter != "auto":
            return self.linter
        if shutil.which(self.verilator):
            return "verilator"
        if shutil.which(self.iverilog):
            return "iverilog"
        raise RuntimeError("no Verilog compiler found for the lint stage (verilator / iverilog)")


def which(exe: str) -> str | None:
    return shutil.which(exe)


def run(cmd: list[str], cwd: Path, timeout: int, tool: str, env: dict | None = None) -> ToolResult:
    """Run *cmd*, never raise; timeouts are reported in the result."""
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, timeout=timeout, env=env, encoding="utf-8", errors="replace")
        return ToolResult(tool=tool, ok=p.returncode == 0, returncode=p.returncode, stdout=p.stdout, stderr=p.stderr, duration_s=time.time() - t0)
    except subprocess.TimeoutExpired as e:
        return ToolResult(
            tool=tool,
            ok=False,
            returncode=-1,
            stdout=(e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or ""),
            stderr=f"timeout after {timeout}s",
            duration_s=time.time() - t0,
            timed_out=True,
        )
    except FileNotFoundError as e:
        return ToolResult(tool=tool, ok=False, returncode=-2, stderr=f"tool not found: {e}", duration_s=time.time() - t0)
