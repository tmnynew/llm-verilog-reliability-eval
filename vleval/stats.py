"""Statistics used in the paper: pass@k, problem-clustered bootstrap CI, permutation tests, Cohen's kappa.

The 10 samples of one problem are not independent, so the paper's intervals and tests take the
*problem* as the unit of analysis (§1.2): :func:`cluster_bootstrap_ci` (needs ``numpy``,
``pip install vleval[stats]``), :func:`paired_signflip_p` and :func:`two_sample_permutation_p`.
The sample-level Wilson interval and Fisher test are kept for quick looks at a single problem;
pooling samples across problems with them overstates significance.
"""

from __future__ import annotations

import itertools
import math
from collections.abc import Iterable, Sequence
from fractions import Fraction

#: Seed of the bootstrap used for the published confidence intervals.
PAPER_SEED = 20261114


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


def cluster_bootstrap_ci(problem_rates: Sequence[float], rng=None, n_resamples: int = 20000, level: float = 0.95) -> tuple[float, float]:
    """Percentile bootstrap CI of the mean pass rate, resampling whole problems (needs ``numpy``).

    *problem_rates* holds one pass rate per problem (passes / samples of that problem).  Pass one
    ``numpy.random.default_rng(PAPER_SEED)`` generator through all calls of a report to reproduce
    the published intervals (the calls are made model by model, level by level).
    """
    import numpy as np

    r = np.asarray(problem_rates, float)
    if r.size == 0:
        return (0.0, 0.0)
    rng = rng if rng is not None else np.random.default_rng(PAPER_SEED)
    idx = rng.integers(0, len(r), size=(n_resamples, len(r)))
    means = r[idx].mean(axis=1)
    tail = 100 * (1 - level) / 2
    return (float(np.percentile(means, tail)), float(np.percentile(means, 100 - tail)))


def paired_signflip_p(diffs: Sequence[float | Fraction]) -> float:
    """Two-sided paired permutation (sign-flip) test of "mean per-problem difference = 0", exact.

    Under the null hypothesis the sign of every per-problem difference is arbitrary; the p-value is the
    share of the 2^n sign patterns whose |sum| is at least the observed one.  Zero differences carry no
    information and are dropped.  The sums are accumulated as exact fractions (pass rates are k/n), so
    the full permutation distribution is obtained by dynamic programming instead of enumeration.
    """
    d = [x if isinstance(x, Fraction) else Fraction(x).limit_denominator(10**6) for x in diffs]
    d = [x for x in d if x != 0]
    if not d:
        return 1.0
    obs = abs(sum(d))
    dist: dict[Fraction, int] = {Fraction(0): 1}
    for x in d:
        nxt: dict[Fraction, int] = {}
        for total, ways in dist.items():
            for t in (total + x, total - x):
                nxt[t] = nxt.get(t, 0) + ways
        dist = nxt
    return sum(ways for total, ways in dist.items() if abs(total) >= obs) / 2 ** len(d)


def two_sample_permutation_p(x: Sequence[float], y: Sequence[float]) -> float:
    """Exact two-sided permutation test on the difference of means of two independent groups of problems."""
    allv = [float(v) for v in x] + [float(v) for v in y]
    n, k = len(allv), len(x)
    if k == 0 or k == n:
        return 1.0
    tot = sum(allv)
    obs = abs(sum(allv[:k]) / k - sum(allv[k:]) / (n - k))
    ge = cnt = 0
    for combo in itertools.combinations(allv, k):
        sx = sum(combo)
        ge += abs(sx / k - (tot - sx) / (n - k)) >= obs - 1e-12
        cnt += 1
    return ge / cnt


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
