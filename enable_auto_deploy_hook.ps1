Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptRoot

if (-not (Test-Path -LiteralPath ".git")) {
    throw "Current folder is not a Git repository: $ScriptRoot"
}

if (-not (Test-Path -LiteralPath ".githooks\\post-commit")) {
    throw "Hook file missing: .githooks\\post-commit"
}

git config core.hooksPath .githooks

Write-Host "Auto deploy hook enabled."
Write-Host "hooksPath: $(git config --get core.hooksPath)"
Write-Host "When you commit on 'main', deploy script will run automatically."
Write-Host "Log file: .git\\auto_deploy.log"

