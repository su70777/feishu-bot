param(
    [switch]$NoPause,
    [int]$Port = 8000
)

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppUrl = "http://127.0.0.1:$Port"
$UvicornOut = Join-Path $ProjectDir "uvicorn_stdout.log"
$UvicornErr = Join-Path $ProjectDir "uvicorn_stderr.log"
$TunnelOut = Join-Path $ProjectDir "cloudflared_stdout.log"
$TunnelErr = Join-Path $ProjectDir "cloudflared_stderr.log"
$CloudflaredExe = Join-Path $ProjectDir "tools\cloudflared.exe"
if (-not (Test-Path $CloudflaredExe)) {
    $SearchRoot = Split-Path -Parent $ProjectDir
    $FoundCloudflared = Get-ChildItem -Path $SearchRoot -Recurse -Filter "cloudflared.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($FoundCloudflared) {
        $CloudflaredExe = $FoundCloudflared.FullName
    }
}

Write-Host "Starting Feishu bot service..."
$uvicorn = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq "python.exe" -and $_.CommandLine -like "*uvicorn app:app*--port*$Port*"
} | Select-Object -First 1

if (-not $uvicorn) {
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($listener) {
        $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
        Write-Host "Port $Port is already in use, so the Feishu bot cannot start on $AppUrl."
        if ($owner) {
            Write-Host "Port owner PID: $($owner.ProcessId)"
            Write-Host "Port owner command: $($owner.CommandLine)"
        }
        Write-Host "Stop the service using that port, or start this bot with another port:"
        Write-Host "powershell -ExecutionPolicy Bypass -File `"$ProjectDir\start_feishu_bot.ps1`" -Port 8001"
        if (-not $NoPause) { Pause }
        exit 1
    }

    Start-Process python `
        -WorkingDirectory $ProjectDir `
        -ArgumentList "-m","uvicorn","app:app","--host","127.0.0.1","--port",$Port `
        -RedirectStandardOutput $UvicornOut `
        -RedirectStandardError $UvicornErr `
        -WindowStyle Hidden | Out-Null
}

try {
    $health = $null
    for ($i = 0; $i -lt 15; $i++) {
        try {
            $health = Invoke-WebRequest "$AppUrl/healthz" -UseBasicParsing -TimeoutSec 3
            break
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    if (-not $health) {
        throw "health check failed"
    }
    $healthJson = $health.Content | ConvertFrom-Json
    if (-not $healthJson.ok) {
        throw "health check did not return Feishu bot status"
    }
    Write-Host $health.Content
} catch {
    Write-Host "Bot service failed. Check uvicorn_stderr.log"
    if (-not $NoPause) { Pause }
    exit 1
}

Write-Host "Starting tunnel..."
if (-not (Test-Path $CloudflaredExe)) {
    Write-Host "cloudflared.exe not found: $CloudflaredExe"
    if (-not $NoPause) { Pause }
    exit 1
}

$cloudflared = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq "cloudflared.exe" -and $_.CommandLine -like "*127.0.0.1:$Port*"
} | Select-Object -First 1

if (-not $cloudflared) {
    Start-Process $CloudflaredExe `
        -ArgumentList "tunnel","--url",$AppUrl `
        -RedirectStandardOutput $TunnelOut `
        -RedirectStandardError $TunnelErr `
        -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "Feishu bot is running."
Write-Host "Health: $AppUrl/healthz"
Write-Host "Tunnel log: $TunnelErr"
Write-Host ""
Write-Host "If Feishu stops replying, run start_feishu_bot.bat again."

if (-not $NoPause) { Pause }
