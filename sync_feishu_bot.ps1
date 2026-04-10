param(
    [string]$ServerHost = "49.235.146.240",
    [string]$ServerUser = "root",
    [string]$RemoteDir = "/root/feishu-bot",
    [string]$ServiceName = "feishu-bot",
    [string]$KeyPath = "",
    [switch]$IncludeData,
    [switch]$NoRestart,
    [switch]$NoPause,
    [switch]$AllowPasswordLogin
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "WARN: $Message" -ForegroundColor Yellow
}

function Assert-CommandExists {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Command not found: $Name. Please install Windows OpenSSH Client (ssh/scp) and tar."
    }
}

function Invoke-CheckedNative {
    param(
        [scriptblock]$Command,
        [string]$StepName
    )
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$StepName failed, ExitCode=$LASTEXITCODE"
    }
}

function Resolve-DefaultKeyPath {
    if ($env:FEISHU_BOT_SSH_KEY) {
        $explicit = $env:FEISHU_BOT_SSH_KEY.Trim()
        if ($explicit) {
            return $explicit
        }
    }

    $candidateRoots = @()
    if ($env:USERPROFILE) {
        $candidateRoots += $env:USERPROFILE
    }
    if ($env:HOME) {
        $candidateRoots += $env:HOME
    }
    $candidateRoots += "C:\Users\Administrator"
    $candidateRoots += "C:\Users\admin"
    $candidateRoots += "C:\Users\Default"
    $candidateRoots = $candidateRoots | Where-Object { $_ } | Select-Object -Unique

    $candidates = @(
        "feishu_bot_sync",
        "feishu_bot_server",
        "feishu_bot_49_235_146_240",
        "id_ed25519",
        "id_rsa"
    )

    foreach ($root in $candidateRoots) {
        foreach ($name in $candidates) {
            $candidate = Join-Path $root ".ssh\$name"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    return ""
}

function New-SshCommonArgs {
    param(
        [string]$PrivateKeyPath,
        [switch]$ForcePublicKeyOnly
    )

    $args = @("-o", "StrictHostKeyChecking=accept-new")
    if ($PrivateKeyPath) {
        $args += @("-i", $PrivateKeyPath)
    }
    if ($ForcePublicKeyOnly) {
        $args += @(
            "-o", "BatchMode=yes",
            "-o", "IdentitiesOnly=yes",
            "-o", "PreferredAuthentications=publickey",
            "-o", "PasswordAuthentication=no",
            "-o", "NumberOfPasswordPrompts=0"
        )
    }
    return $args
}

function Test-SshKeyLogin {
    param(
        [string]$User,
        [string]$ServerHostName,
        [string]$PrivateKeyPath
    )

    $sshArgs = New-SshCommonArgs -PrivateKeyPath $PrivateKeyPath -ForcePublicKeyOnly
    $sshArgs += @("-o", "ConnectTimeout=8", ("{0}@{1}" -f $User, $ServerHostName))
    & ssh @sshArgs "id -u" *> $null
    return ($LASTEXITCODE -eq 0)
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path -LiteralPath (Join-Path $ScriptRoot "app.py"))) {
    throw "Run this script from the Feishu bot project root."
}

Assert-CommandExists "ssh"
Assert-CommandExists "scp"
Assert-CommandExists "tar"

$DefaultKeyPath = Resolve-DefaultKeyPath
if (-not $KeyPath -and $DefaultKeyPath) {
    $KeyPath = $DefaultKeyPath
    Write-Step "Detected SSH key: $KeyPath"
}

if (-not $KeyPath -and -not $AllowPasswordLogin) {
    throw "No SSH private key found. Put the private key at .ssh\feishu_bot_server (or pass -KeyPath), or run with -AllowPasswordLogin if you really want password mode."
}

if ($KeyPath -and -not $ServerUser) {
    $loginCandidates = @("ubuntu", "root")
    $chosenUser = $null
    foreach ($candidate in $loginCandidates) {
        Write-Step "Testing SSH key login as $candidate..."
        if (Test-SshKeyLogin -User $candidate -ServerHostName $ServerHost -PrivateKeyPath $KeyPath) {
            $chosenUser = $candidate
            break
        }
    }
    if (-not $chosenUser) {
        throw "SSH key login failed for both ubuntu and root. Please make sure the matching public key is installed on the server, then try again."
    }
    $ServerUser = $chosenUser
    Write-Step "Using SSH key login as $ServerUser."
}

$remoteTarget = "$ServerUser@$ServerHost"
$sshCommonArgs = if ($KeyPath) { New-SshCommonArgs -PrivateKeyPath $KeyPath -ForcePublicKeyOnly } else { New-SshCommonArgs }
$syncItems = @(
    "app.py",
    "requirements.txt",
    ".env",
    ".env.example",
    "deploy"
)
if ($IncludeData) {
    $syncItems += "data"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "feishu-bot-sync"
$stageDir = Join-Path $tempRoot ("stage_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
$archivePath = Join-Path $tempRoot "feishu-bot-sync.tar.gz"

try {
    Write-Step "Prepare temp directory"
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    Write-Step "Collect files to upload"
    foreach ($item in $syncItems) {
        $src = Join-Path $ScriptRoot $item
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Warn "Skip missing item: $item"
            continue
        }

        $dst = Join-Path $stageDir $item
        $info = Get-Item -LiteralPath $src
        if ($info.PSIsContainer) {
            Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
        } else {
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }

    Write-Step "Package upload contents"
    Push-Location $stageDir
    try {
        Invoke-CheckedNative -StepName "Local packaging" -Command { tar -czf $archivePath . }
    } finally {
        Pop-Location
    }

    Write-Step "Upload to server"
    $scpArgs = @()
    $scpArgs += $sshCommonArgs
    $scpArgs += @($archivePath, ("{0}:/tmp/feishu-bot-sync.tar.gz" -f $remoteTarget))
    & scp @scpArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Upload failed, ExitCode=$LASTEXITCODE"
    }

    if (-not $NoRestart) {
        Write-Step "Extract on server and restart service"
        $remoteScriptTemplate = @'
set -e
if [ "$(id -u)" -ne 0 ] && ! sudo -n true >/dev/null 2>&1; then
  echo "sudo -n is unavailable for user $(id -un). Please install a passwordless sudo setup or use a root SSH key."
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  mkdir -p "__REMOTE_DIR__"
  tar -xzf /tmp/feishu-bot-sync.tar.gz -C "__REMOTE_DIR__"
else
  sudo -n mkdir -p "__REMOTE_DIR__"
  sudo -n tar -xzf /tmp/feishu-bot-sync.tar.gz -C "__REMOTE_DIR__"
fi
rm -f /tmp/feishu-bot-sync.tar.gz
if [ "$(id -u)" -eq 0 ]; then
  systemctl restart "__SERVICE_NAME__"
else
  sudo -n systemctl restart "__SERVICE_NAME__"
fi
systemctl is-active --quiet "__SERVICE_NAME__"
for i in $(seq 1 15); do
  if curl -fsS http://127.0.0.1:8000/healthz >/dev/null; then
    echo "healthz ok"
    exit 0
  fi
  sleep 1
done
echo "healthz check failed"
exit 1
'@
        $remoteScript = $remoteScriptTemplate.Replace("__REMOTE_DIR__", $RemoteDir).Replace("__SERVICE_NAME__", $ServiceName)
        $sshArgs = @()
        $sshArgs += $sshCommonArgs
        $sshArgs += $remoteTarget
        $remoteScript | & ssh @sshArgs "bash -s"
        if ($LASTEXITCODE -ne 0) {
            throw "Remote restart or health check failed, ExitCode=$LASTEXITCODE"
        }
    } else {
        Write-Warn "Restart skipped. You can restart later with: sudo systemctl restart $ServiceName"
    }

    Write-Step "Done"
    Write-Host "Sync and restart completed."
    Write-Host "Remote dir: $RemoteDir"
    Write-Host "Service name: $ServiceName"
}
finally {
    if (Test-Path -LiteralPath $stageDir) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
    }
    if (-not $NoPause) {
        try {
            if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
                Write-Host ""
                Write-Host "Press any key to exit..." -ForegroundColor DarkGray
                [void][System.Console]::ReadKey($true)
            }
        } catch {
            # Ignore pause errors in non-interactive environments.
        }
    }
}
