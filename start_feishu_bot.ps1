param(
    [switch]$NoPause
)

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppUrl = "http://127.0.0.1:8000"
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
    $_.Name -eq "python.exe" -and $_.CommandLine -like "*uvicorn app:app*8000*"
} | Select-Object -First 1

if (-not $uvicorn) {
    Start-Process python `
        -WorkingDirectory $ProjectDir `
        -ArgumentList "-m","uvicorn","app:app","--host","127.0.0.1","--port","8000" `
        -RedirectStandardOutput $UvicornOut `
        -RedirectStandardError $UvicornErr | Out-Null
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
    $_.Name -eq "cloudflared.exe" -and $_.CommandLine -like "*127.0.0.1:8000*"
} | Select-Object -First 1

if (-not $cloudflared) {
    Start-Process $CloudflaredExe `
        -ArgumentList "tunnel","--url",$AppUrl `
        -RedirectStandardOutput $TunnelOut `
        -RedirectStandardError $TunnelErr | Out-Null
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "Feishu bot is running."
Write-Host "Health: $AppUrl/healthz"
Write-Host "Tunnel log: $TunnelErr"
Write-Host ""
Write-Host "If Feishu stops replying, run start_feishu_bot.bat again."

if (-not $NoPause) { Pause }
