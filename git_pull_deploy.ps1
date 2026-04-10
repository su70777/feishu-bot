param(
    [string]$ServerHost = "49.235.146.240",
    [string]$ServerUser = "root",
    [string]$RemoteWorkTree = "/root/feishu-bot",
    [string]$Branch = "main",
    [string]$RemoteName = "origin",
    [string]$ServiceName = "feishu-bot",
    [string]$KeyPath = "",
    [string]$CommitMessage = "",
    [switch]$AutoCommit,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Resolve-DefaultKeyPath {
    if ($env:FEISHU_BOT_SSH_KEY) {
        $explicit = $env:FEISHU_BOT_SSH_KEY.Trim()
        if ($explicit) { return $explicit }
    }

    $candidates = @(
        "$env:USERPROFILE\.ssh\feishu_bot_sync",
        "$env:USERPROFILE\.ssh\feishu_bot_server",
        "$env:USERPROFILE\.ssh\id_ed25519",
        "$env:USERPROFILE\.ssh\id_rsa"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return ""
}

function Run-NativeChecked {
    param(
        [scriptblock]$Action,
        [string]$Name
    )
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed, ExitCode=$LASTEXITCODE"
    }
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptRoot

if (-not (Test-Path -LiteralPath ".git")) {
    throw "Current folder is not a Git repository: $ScriptRoot"
}

if (-not $KeyPath) {
    $KeyPath = Resolve-DefaultKeyPath
}
if (-not $KeyPath) {
    throw "No SSH key found. Set -KeyPath or FEISHU_BOT_SSH_KEY."
}

$normalizedKeyPath = ($KeyPath -replace "\\", "/")
$sshCommand = "ssh -i '$normalizedKeyPath' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
git config core.sshCommand $sshCommand | Out-Null

if ($AutoCommit) {
    Write-Step "Auto commit local changes"
    git add -A
    if ((git status --porcelain).Length -gt 0) {
        if (-not $CommitMessage) {
            $CommitMessage = "chore: update bot at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        }
        Run-NativeChecked -Name "git commit" -Action { git commit -m $CommitMessage }
    } else {
        Write-Host "No local changes to commit."
    }
}

Write-Step "Push code to remote Git repository"
Run-NativeChecked -Name "git push" -Action { git push $RemoteName $Branch }

Write-Step "Trigger server git pull + restart"
$remoteTarget = "$ServerUser@$ServerHost"
$remoteScript = @"
set -e
cd $RemoteWorkTree
git pull --ff-only $RemoteName $Branch
if [ -f requirements.txt ]; then
  /root/feishu-bot/.venv/bin/pip install -q -r requirements.txt || true
fi
systemctl restart $ServiceName
sleep 2
systemctl is-active $ServiceName
curl -fsS http://127.0.0.1:8000/healthz
"@
$remoteScript = $remoteScript -replace "`r`n", "`n"

Run-NativeChecked -Name "remote deploy" -Action {
    $remoteScript | & ssh -i $KeyPath -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new $remoteTarget "bash -s"
}

Write-Step "Done"
Write-Host "Git deploy completed."

if (-not $NoPause) {
    try {
        if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
            Write-Host ""
            Write-Host "Press any key to exit..." -ForegroundColor DarkGray
            [void][System.Console]::ReadKey($true)
        }
    } catch {
    }
}
