Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptRoot

if (-not (Test-Path -LiteralPath ".git")) {
    throw "Current folder is not a Git repository: $ScriptRoot"
}

git config --unset core.hooksPath
Write-Host "Auto deploy hook disabled."

