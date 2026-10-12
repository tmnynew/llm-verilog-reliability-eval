"""LLM access layer.

* :class:`OpenAICompatClient` talks to any OpenAI-compatible chat endpoint
  (cloud APIs, vLLM for the local 7B model, …).
* :class:`ResponseCache` makes runs reproducible and lets teachers pre-generate
  all classroom samples once (paper §2.3: no API calls during class).
* :class:`GoldenOracleClient` is an offline stand-in that returns the golden
  model – used by CI and by ``vleval selftest`` to validate the whole pipeline
  without spending tokens.
"""

from __future__ import annotations

import hashlib
import json
import os
import random
import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

import requests

Message = dict[str, str]


@dataclass
class ModelConfig:
    name: str  # label used in reports (may be anonymised, e.g. "Model A")
    model: str  # provider model id
    base_url: str
    api_key_env: str = "OPENAI_API_KEY"
    api_key: str = ""  # literal key (configs/models.yaml is git-ignored); takes precedence over api_key_env
    temperature: float = 0.2
    max_tokens: int = 2048
    timeout_s: int = 120
    max_concurrency: int = 2  # simultaneous HTTP requests to this endpoint (EDA jobs stay fully parallel)
    retries: int = 8  # 429/5xx retries with exponential back-off (1 s … 60 s, honours Retry-After)
    extra: dict[str, object] = None  # type: ignore[assignment]

    @staticmethod
    def from_dict(d: dict) -> ModelConfig:
        return ModelConfig(
            name=d["name"],
            model=d["model"],
            base_url=d["base_url"].rstrip("/"),
            api_key_env=d.get("api_key_env", "OPENAI_API_KEY"),
            api_key=str(d.get("api_key", "") or ""),
            temperature=float(d.get("temperature", 0.2)),
            max_tokens=int(d.get("max_tokens", 2048)),
            timeout_s=int(d.get("timeout_s", 120)),
            max_concurrency=max(1, int(d.get("max_concurrency", 2))),
            retries=max(1, int(d.get("retries", 8))),
            extra=dict(d.get("extra", {})),
        )

    def resolve_api_key(self) -> str:
        return self.api_key or os.environ.get(self.api_key_env, "")


@dataclass
class Completion:
    text: str
    model_version: str
    cached: bool
    latency_s: float


class ChatClient(Protocol):
    def complete(self, messages: list[Message], *, temperature: float, seed_index: int) -> Completion: ...


class ResponseCache:
    """SQLite cache keyed by (model, messages, temperature, sample index)."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # Shared by the runner's worker threads: allow cross-thread use and serialise access.
        self.conn = sqlite3.connect(self.path, check_same_thread=False)
        self._lock = threading.Lock()
        with self._lock:
            self.conn.execute("CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, text TEXT, model_version TEXT, created_at TEXT)")
            self.conn.commit()

    @staticmethod
    def key(model: str, messages: list[Message], temperature: float, seed_index: int, max_tokens: int | None = None) -> str:
        # max_tokens is part of the key: a reply truncated under a small budget must not be reused
        # when the budget is raised.  ``None`` keeps the historical key layout for old entries.
        parts = [model, messages, round(temperature, 3), seed_index]
        if max_tokens is not None:
            parts.append(max_tokens)
        blob = json.dumps(parts, ensure_ascii=False, sort_keys=True)
        return hashlib.sha256(blob.encode("utf-8")).hexdigest()

    def get(self, key: str) -> Completion | None:
        with self._lock:
            row = self.conn.execute("SELECT text, model_version FROM cache WHERE key=?", (key,)).fetchone()
        return Completion(row[0], row[1], True, 0.0) if row else None

    def put(self, key: str, c: Completion) -> None:
        with self._lock:
            self.conn.execute(
                "INSERT OR REPLACE INTO cache VALUES (?,?,?,?)",
                (key, c.text, c.model_version, time.strftime("%Y-%m-%dT%H:%M:%S")),
            )
            self.conn.commit()


class PermanentLLMError(RuntimeError):
    """4xx response other than 429 – retrying cannot help (bad request, context too long, auth...)."""


class OpenAICompatClient:
    def __init__(self, cfg: ModelConfig, cache: ResponseCache | None = None, retries: int | None = None):
        self.cfg = cfg
        self.cache = cache
        self.retries = retries if retries is not None else cfg.retries
        self.api_key = cfg.resolve_api_key()
        self._sem = threading.BoundedSemaphore(cfg.max_concurrency)

    def complete(self, messages: list[Message], *, temperature: float, seed_index: int) -> Completion:
        key = ResponseCache.key(self.cfg.model, messages, temperature, seed_index, self.cfg.max_tokens)
        if self.cache and (hit := self.cache.get(key)):
            return hit
        payload = {
            "model": self.cfg.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": self.cfg.max_tokens,
            "seed": seed_index,  # honoured by vLLM / OpenAI where supported
            **(self.cfg.extra or {}),
        }
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        last_err: Exception | None = None
        for attempt in range(self.retries):
            t0 = time.time()
            retry_after: float | None = None
            try:
                with self._sem:
                    r = requests.post(f"{self.cfg.base_url}/chat/completions", json=payload, headers=headers, timeout=self.cfg.timeout_s)
                if r.status_code == 429 or r.status_code >= 500:
                    ra = r.headers.get("Retry-After")
                    retry_after = float(ra) if ra and ra.replace(".", "", 1).isdigit() else None
                    raise RuntimeError(f"HTTP {r.status_code}: {r.text[:200]}")
                if r.status_code >= 400:  # client error: not retriable, keep the server's reason
                    raise PermanentLLMError(f"HTTP {r.status_code}: {r.text[:400]}")
                data = r.json()
                text = data["choices"][0]["message"]["content"]
                comp = Completion(text, data.get("model", self.cfg.model), False, time.time() - t0)
                if self.cache:
                    self.cache.put(key, comp)
                return comp
            except PermanentLLMError:
                raise
            except Exception as e:  # network / rate-limit – exponential back-off
                last_err = e
                if attempt + 1 < self.retries:
                    delay = retry_after if retry_after else min(60.0, 2.0**attempt)
                    time.sleep(delay + random.uniform(0, 1))
        raise RuntimeError(f"LLM call failed after {self.retries} attempts: {last_err}")


class GoldenOracleClient:
    """Offline client returning the golden model (optionally a mutant) – for self-tests."""

    def __init__(self, benchmark, mutant_id: str | None = None):
        self.benchmark = benchmark
        self.mutant_id = mutant_id

    def complete(self, messages: list[Message], *, temperature: float, seed_index: int) -> Completion:
        # The module name is embedded in the interface header of the user prompt.
        import re

        m = re.search(r"module\s+(\w+)", messages[-1]["content"])
        if not m:
            raise ValueError("oracle could not find module name in prompt")
        problem = next(p for p in self.benchmark if p.interface.module == m.group(1))
        path = problem.golden_path if not self.mutant_id else problem.mutants_dir / f"{self.mutant_id}.v"
        code = path.read_text(encoding="utf-8")
        return Completion(f"```verilog\n{code}\n```", "golden-oracle", False, 0.0)


def load_model_configs(path: Path) -> list[ModelConfig]:
    import yaml

    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    return [ModelConfig.from_dict(d) for d in data["models"]]
