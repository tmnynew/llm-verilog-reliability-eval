"""Statistics used in the paper: pass@k, Wilson CI, Fisher exact test, Cohen's kappa.

Only the standard library is required; ``scipy`` is used for Fisher's test
when available and a pure-Python hypergeometric fallback is used otherwise.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Sequence


def pass_at_k(n: int, c: int, k: int) -> float:
    """Unbiased estimator of pass@k (Chen et al., 2021)."""
    if n - c < k:
        return 1.0
    return 1.0 - math.prod((n - c - i) / (n - i) for i in range(k))


def wilson_ci(successes: int, total: int, z: float = 1.959964) -> tuple[float, float]:
    """Wilson score interval for a binomial proportion."""
    if total == 0:
        return (0.0, 0.0)
    p = successes / total
    denom = 1 + z * z / total
    centre = (p + z * z / (2 * total)) / denom
    half = z * math.sqrt(p * (1 - p) / total + z * z / (4 * total * total)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def fisher_exact(a: int, b: int, c: int, d: int) -> float:
    """Two-sided Fisher exact test p-value for the 2x2 table [[a, b], [c, d]]."""
    try:
        from scipy.stats import fisher_exact as _fe  # type: ignore

        return float(_fe([[a, b], [c, d]])[1])
    except Exception:  # pragma: no cover - exercised only without scipy
        return _fisher_fallback(a, b, c, d)


def _fisher_fallback(a: int, b: int, c: int, d: int) -> float:
    n = a + b + c + d
    r1, c1 = a + b, a + c

    def pmf(x: int) -> float:
        return math.exp(
            math.lgamma(r1 + 1)
            - math.lgamma(x + 1)
            - math.lgamma(r1 - x + 1)
            + math.lgamma(n - r1 + 1)
            - math.lgamma(c1 - x + 1)
            - math.lgamma(n - r1 - c1 + x + 1)
            - (math.lgamma(n + 1) - math.lgamma(c1 + 1) - math.lgamma(n - c1 + 1))
        )

    lo, hi = max(0, c1 - (n - r1)), min(r1, c1)
    p_obs = pmf(a)
    return min(1.0, sum(pmf(x) for x in range(lo, hi + 1) if pmf(x) <= p_obs * (1 + 1e-9)))


def cohen_kappa(r1: Sequence[str], r2: Sequence[str]) -> float:
    """Cohen's kappa between two raters' categorical labels."""
    if len(r1) != len(r2) or not r1:
        raise ValueError("rater sequences must be same non-zero length")
    n = len(r1)
    cats = set(r1) | set(r2)
    po = sum(1 for x, y in zip(r1, r2, strict=True) if x == y) / n
    pe = sum((list(r1).count(c) / n) * (list(r2).count(c) / n) for c in cats)
    return 1.0 if pe == 1 else (po - pe) / (1 - pe)


def lint_density(functional_warnings: int, effective_lines: int) -> float:
    """Functional lint warnings per 100 effective lines."""
    return 0.0 if effective_lines == 0 else 100.0 * functional_warnings / effective_lines


def fmax_from_wns(period_ns: float, wns_ns: float) -> float:
    """F_max = 1 / (T_clk - WNS) in MHz (paper Sec. 1.2)."""
    return 1000.0 / (period_ns - wns_ns)


def summarize_binary(values: Iterable[bool]) -> dict[str, float]:
    vals = list(values)
    k, n = sum(vals), len(vals)
    lo, hi = wilson_ci(k, n)
    return {"n": n, "k": k, "rate": k / n if n else 0.0, "ci_low": lo, "ci_high": hi}


def repair_curve(rounds_to_pass: list[int], max_rounds: int = 3) -> list[float]:
    """Cumulative pass rate after round 0..max_rounds; -1 means never passed."""
    n = len(rounds_to_pass)
    return [sum(1 for r in rounds_to_pass if 0 <= r <= k) / n if n else 0.0 for k in range(max_rounds + 1)]
