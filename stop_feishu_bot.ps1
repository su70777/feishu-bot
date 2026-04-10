$pythonTargets = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq "python.exe" -and $_.CommandLine -like "*uvicorn app:app*8000*"
}

foreach ($p in $pythonTargets) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}

$tunnelTargets = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq "cloudflared.exe" -and $_.CommandLine -like "*127.0.0.1:8000*"
}

foreach ($p in $tunnelTargets) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}

Write-Host "Feishu bot and tunnel stopped."
Pause
