# Runs the evaluation described in paper §4 (Model A–D) and produces the report.
# Prerequisites:
#   1. configs/models.yaml exists (copied from models.example.yaml) with either a literal
#      `api_key:` per model or the named `api_key_env` variable set in this shell.
#   2. OSS CAD Suite (Verilator/Icarus/Yosys) under C:\tools\oss-cad-suite; Vivado 2024.1
#      under C:\Xilinx (pass -Vivado to use it as the authoritative synthesis judge).
#
# Usage (from the repository root):
#   powershell -File scripts\run_paper_eval.ps1 [-Models "Model B,Model C"] [-Vivado] [-Workers 5] [-SkipSmoke]
# The run is resumable: re-running skips samples already in results/results.db.
param(
    [string]$Models = "Model A,Model B,Model C,Model D",
    [switch]$Vivado,
    [switch]$SkipSmoke,
    [int]$Workers = 5,
    [string]$Tools = "C:\tools\tools_local.yaml"
)

$ErrorActionPreference = "Stop"
$env:PYTHONIOENCODING = "utf-8"
if (-not ($env:PATH -like "*oss-cad-suite*")) {
    $env:PATH = "C:\tools\oss-cad-suite\bin;C:\tools\oss-cad-suite\lib;" + $env:PATH
    $env:VERILATOR_ROOT = "C:\tools\oss-cad-suite\share\verilator"
}
$vivadoBin = "C:\Xilinx\Vivado\2024.1\bin"
if ((Test-Path $vivadoBin) -and ($env:PATH -notlike "*$vivadoBin*")) { $env:PATH = "$vivadoBin;" + $env:PATH }

$common = @("--tools", $Tools)
if ($Vivado) { $common += "--vivado" }
$selected = $Models.Split(",") | ForEach-Object { $_.Trim() }

if (-not $SkipSmoke) {
    Write-Host "== Step 0: endpoint connectivity ($Models) =="
    $py = @"
import sys
from pathlib import Path
from vleval.llm import load_model_configs, OpenAICompatClient
want = set(x.strip() for x in sys.argv[1].split(','))
bad = 0
for cfg in load_model_configs(Path('configs/models.yaml')):
    if cfg.name not in want: continue
    try:
        r = OpenAICompatClient(cfg, None, retries=1).complete([{'role':'user','content':'Reply with the single word OK.'}], temperature=0.0, seed_index=0)
        print(f'  {cfg.name}: OK ({r.model_version}, {r.latency_s:.1f}s)')
    except Exception as e:
        bad += 1; print(f'  {cfg.name}: FAIL {str(e)[:200]}')
sys.exit(1 if bad else 0)
"@
    python -c $py $Models
    if ($LASTEXITCODE -ne 0) { throw "Connectivity test failed for at least one model; fix keys/billing before the full run." }
}

if ($selected -contains "Model B") {
    Write-Host "== Model B: all 8 spec x strategy configurations (paper §3 / §4.3) =="
    python -m vleval.cli @common run --model "Model B" --specs brief,detailed --strategies zero,few,constraint,cot `
        --n 10 --temperature 0.2 --repair 3 --workers $Workers
    if ($LASTEXITCODE -ne 0) { throw "Model B run failed (re-run this script to resume)." }
}

$others = $selected | Where-Object { $_ -ne "Model B" }
if ($others) {
    $list = $others -join ","
    Write-Host "== $list : main configuration only (detailed x zero) =="
    python -m vleval.cli @common run --model $list --specs detailed --strategies zero `
        --n 10 --temperature 0.2 --repair 3 --workers $Workers
    if ($LASTEXITCODE -ne 0) { throw "Main-configuration run failed (re-run this script to resume)." }
}

Write-Host "== Report =="
python -m vleval.cli report --db results/results.db --out results/report
Write-Host "Done. Tables: results/report/tables.md ; figures: results/report/*.png ; summary: results/report/summary.json"
