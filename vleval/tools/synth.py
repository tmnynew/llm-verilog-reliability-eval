"""Synthesis back-ends.

* :class:`Yosys` – second-level pre-screen used in the interactive student flow
  and as CI fallback (``synth_xilinx``; latch = LD* cells or ``$dlatch``).
* :class:`Vivado` – authoritative judge (paper §2.3 ⑤): out-of-context
  synthesis + implementation on xc7a35t with a 200 MHz constraint; parses
  utilisation, latch inference and WNS.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

from ..models import ToolResult
from ..stats import fmax_from_wns
from .base import ToolConfig, run

# --------------------------------------------------------------------------- #
# Yosys
# --------------------------------------------------------------------------- #
# `stat` prints "<name> <count>" (Yosys ≤ 0.35) or "<count> <name>" (newer); accept both.
_YS_CELL_RE = re.compile(r"^\s*(?:(\$?_?[A-Za-z][A-Za-z0-9_$]*)\s+(\d+)|(\d+)\s+(\$?_?[A-Za-z][A-Za-z0-9_$]*))\s*$", re.M)


class Yosys:
    def __init__(self, cfg: ToolConfig):
        self.cfg = cfg

    def synth(self, dut: Path, top: str, workdir: Path) -> ToolResult:
        stat_file = workdir / "yosys_stat.txt"
        script = (
            f"read_verilog {dut.as_posix()}; hierarchy -check -top {top}; "
            # Run the Xilinx flow up to LUT mapping, then map with classic ABC: the abc9/xaiger2 path is
            # experimental and crashes on some builds; results only serve as a pre-screen anyway.
            f"synth_xilinx -top {top} -flatten -noiopad -run begin:map_luts; abc -lut 2:6; opt_clean; "
            f"tee -q -o {stat_file.as_posix()} stat"
        )
        # ABC (called by synth_xilinx) is sensitive to exotic TMP paths on Windows – keep it inside the work dir.
        env = dict(os.environ, TMP=str(workdir), TEMP=str(workdir), TMPDIR=str(workdir))
        res = run([self.cfg.yosys, "-Q", "-T", "-q", "-p", script], workdir, self.cfg.synth_timeout_s, "yosys", env=env)
        text = res.stdout + res.stderr
        if stat_file.exists():
            text += "\n" + stat_file.read_text(encoding="utf-8", errors="replace")
        cells: dict[str, int] = {}
        for n1, c1, c2, n2 in _YS_CELL_RE.findall(text):
            name, n = (n1, c1) if n1 else (n2, c2)
            cells[name] = cells.get(name, 0) + int(n)
        lut = sum(v for k, v in cells.items() if re.fullmatch(r"LUT\d|\$lut", k))
        ff = sum(v for k, v in cells.items() if re.fullmatch(r"FD[RSCP]E", k))
        latch = sum(v for k, v in cells.items() if re.fullmatch(r"LD[CP]E|\$_?DLATCH\w*|\$dlatch", k))
        res.data.update({"LUT": lut, "FF": ff, "latch": latch, "cells": cells})
        res.ok = res.returncode == 0 and "ERROR" not in text
        return res


# --------------------------------------------------------------------------- #
# Vivado
# --------------------------------------------------------------------------- #
_VIVADO_TCL = """\
set_param general.maxThreads 4
read_verilog {dut}
synth_design -top {top} -part {part} -mode out_of_context
{clock_cmd}
opt_design
place_design
route_design
report_utilization -file util.rpt
report_timing_summary -file timing.rpt
exit
"""
_LATCH_WARN_RE = re.compile(r"\[Synth 8-327\]", re.I)
_SYNTH_ERR_RE = re.compile(r"^ERROR:\s*\[(Synth|Common|Vivado)[^\]]*\].*$", re.M)
_UTIL_ROW_RE = re.compile(r"^\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|", re.M)
_WNS_HDR_RE = re.compile(r"WNS\(ns\)\s+TNS\(ns\).*?\n[-\s]+\n\s*(-?[\d.]+)", re.S)


class Vivado:
    def __init__(self, cfg: ToolConfig):
        self.cfg = cfg

    def synth_impl(self, dut: Path, top: str, workdir: Path, clock_port: str | None) -> ToolResult:
        clock_cmd = f"create_clock -period {self.cfg.clock_period_ns} [get_ports {clock_port}]" if clock_port else ""
        tcl = workdir / "run.tcl"
        tcl.write_text(_VIVADO_TCL.format(dut=dut.as_posix(), top=top, part=self.cfg.fpga_part, clock_cmd=clock_cmd), encoding="utf-8")
        res = run([self.cfg.vivado, "-mode", "batch", "-nolog", "-nojournal", "-source", str(tcl)], workdir, self.cfg.synth_timeout_s, "vivado")
        log = res.stdout + res.stderr
        error_lines = [m.group(0) for m in _SYNTH_ERR_RE.finditer(log)]
        res.ok = res.returncode == 0 and not error_lines
        res.data["error_lines"] = error_lines[:5]
        res.data["latch_warnings"] = len(_LATCH_WARN_RE.findall(log))
        util = workdir / "util.rpt"
        if util.exists():
            res.data.update(self.parse_utilization(util.read_text(encoding="utf-8", errors="replace")))
        timing = workdir / "timing.rpt"
        if timing.exists() and clock_port:
            wns = self.parse_wns(timing.read_text(encoding="utf-8", errors="replace"))
            if wns is not None:
                res.data["WNS_ns"] = wns
                res.data["Fmax_MHz"] = fmax_from_wns(self.cfg.clock_period_ns, wns)
        res.data["latch"] = res.data.get("latch", 0) or res.data["latch_warnings"]
        return res

    @staticmethod
    def parse_utilization(text: str) -> dict[str, int]:
        out: dict[str, int] = {}
        for name, val in _UTIL_ROW_RE.findall(text):
            key = name.strip()
            if key in ("Slice LUTs", "Slice LUTs*", "LUT as Logic"):
                out.setdefault("LUT", int(val))
            elif key in ("Register as Flip Flop", "Slice Registers"):
                out.setdefault("FF", int(val))
            elif key == "Register as Latch":
                out["latch"] = int(val)
        return out

    @staticmethod
    def parse_wns(text: str) -> float | None:
        m = _WNS_HDR_RE.search(text)
        return float(m.group(1)) if m else None
