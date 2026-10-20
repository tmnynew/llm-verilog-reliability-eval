"""Minimal student-facing web UI (paper §2.3: students never touch API keys).

Endpoints
---------
GET  /                      problem list
GET  /problem/{id}          spec (detailed) + interface + submission form
POST /judge                 judge pasted Verilog (Yosys pre-screen only, seconds)
GET  /api/problems          JSON list
POST /api/judge             JSON {problem_id, code} → verdict

Per-user quota is enforced by a simple in-memory counter keyed on the
``X-Student-Id`` header (replace with the campus SSO in production).
Run with ``vleval web``; requires ``pip install vleval[web]``.
"""

from __future__ import annotations

import html
from collections import defaultdict
from pathlib import Path

from ..benchmark import Benchmark
from ..judge import Judge
from ..models import SpecVersion
from ..tools import ToolConfig

_PAGE = """<!doctype html><html lang="zh"><head><meta charset="utf-8"><title>Verilog 评测</title>
<style>body{{font-family:system-ui;margin:2em;max-width:900px}}pre{{background:#f4f4f4;padding:1em;overflow:auto}}
textarea{{width:100%;height:20em;font-family:monospace}}.fail{{color:#b00}}.pass{{color:#080}}</style></head><body>{body}</body></html>"""


def create_app(bench: Benchmark, tools: ToolConfig, quota: int = 120):
    from fastapi import FastAPI, Form, Header, HTTPException
    from fastapi.responses import HTMLResponse

    app = FastAPI(title="vleval")
    judge = Judge(tools)
    usage: dict[str, int] = defaultdict(int)

    def _check_quota(student: str) -> None:
        usage[student] += 1
        if usage[student] > quota:
            raise HTTPException(429, f"quota of {quota} judgements exceeded")

    @app.get("/", response_class=HTMLResponse)
    def index():
        items = "".join(f'<li><a href="/problem/{p.id}">{p.level.value} · {html.escape(p.title)}</a></li>' for p in bench)
        return _PAGE.format(body=f"<h1>评测题库</h1><ul>{items}</ul>")

    @app.get("/problem/{pid}", response_class=HTMLResponse)
    def problem(pid: str):
        p = bench.get(pid)
        body = (
            f"<h1>{html.escape(p.title)}</h1><h2>功能规范</h2><pre>{html.escape(p.spec(SpecVersion.DETAILED))}</pre>"
            f"<h2>接口</h2><pre>{html.escape(p.interface.to_verilog_header())}\nendmodule</pre>"
            f'<h2>提交代码</h2><form method="post" action="/judge"><input type="hidden" name="problem_id" value="{p.id}">'
            f'<textarea name="code"></textarea><br><button>评测</button></form>'
        )
        return _PAGE.format(body=body)

    @app.post("/judge", response_class=HTMLResponse)
    def judge_form(problem_id: str = Form(...), code: str = Form(...), x_student_id: str = Header("anonymous")):
        _check_quota(x_student_id)
        v = judge.judge(bench.get(problem_id), code)
        cls = "pass" if v.passed else "fail"
        fails = "".join(f"<li>{html.escape(f)}</li>" for f in v.failed_cases[:10])
        body = (
            f'<h1 class="{cls}">{"通过" if v.passed else "未通过：" + v.stage.value}</h1>'
            f"<p>错误类别：{', '.join(e.value + ' ' + e.label for e in v.errors) or '—'}</p>"
            f"<p>Lint：{html.escape(str(v.lint_counts))}　资源：{html.escape(str(v.resources))}</p><ul>{fails}</ul>"
            f'<p><a href="/problem/{problem_id}">返回</a></p>'
        )
        return _PAGE.format(body=body)

    @app.get("/api/problems")
    def api_problems():
        return [{"id": p.id, "level": p.level.value, "title": p.title, "module": p.interface.module} for p in bench]

    @app.post("/api/judge")
    def api_judge(payload: dict, x_student_id: str = Header("anonymous")):
        _check_quota(x_student_id)
        v = judge.judge(bench.get(payload["problem_id"]), payload["code"])
        return {
            "stage": v.stage.value,
            "passed": v.passed,
            "sim_passed": v.sim_passed,
            "synth_ok": v.synth_ok,
            "errors": [e.value for e in v.errors],
            "primary_error": v.primary_error.value if v.primary_error else None,
            "failed_cases": v.failed_cases[:10],
            "lint": v.lint_counts,
            "resources": v.resources,
        }

    return app


def serve(bench: Benchmark, tools: ToolConfig, db: Path, host: str = "127.0.0.1", port: int = 8000) -> None:
    import uvicorn

    uvicorn.run(create_app(bench, tools), host=host, port=port)
