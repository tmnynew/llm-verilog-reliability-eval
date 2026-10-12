import shutil
from pathlib import Path

import pytest

from vleval.benchmark import Benchmark

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="session")
def bench() -> Benchmark:
    return Benchmark(ROOT / "benchmark")


def _has_eda() -> bool:
    return bool(shutil.which("iverilog") or shutil.which("verilator"))


requires_eda = pytest.mark.skipif(not _has_eda(), reason="needs Icarus Verilog or Verilator on PATH")
