param()
$ErrorActionPreference = 'Stop'
$codeMapProjectRoot = Split-Path -Parent $PSScriptRoot
$codeMapPython = Join-Path $codeMapProjectRoot '.skill-tools\graphify\venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $codeMapPython)) {
    throw 'Project-local Graphify environment is missing. See docs/agents/skill-packs.md.'
}
Push-Location -LiteralPath $codeMapProjectRoot
$codeMapPreviousUtf8 = $env:PYTHONUTF8
$codeMapPreviousBackend = $env:GRAPHIFY_BACKEND
try {
    $env:PYTHONUTF8 = '1'
    $env:GRAPHIFY_BACKEND = 'none'
    & $codeMapPython -m graphify extract . --code-only --max-workers 2
    if ($LASTEXITCODE -ne 0) { throw "Graphify extraction failed with exit code $LASTEXITCODE" }
    & $codeMapPython -m graphify cluster-only . --no-label
    if ($LASTEXITCODE -ne 0) { throw "Graphify report generation failed with exit code $LASTEXITCODE" }
} finally {
    $env:PYTHONUTF8 = $codeMapPreviousUtf8
    $env:GRAPHIFY_BACKEND = $codeMapPreviousBackend
    Pop-Location
}
