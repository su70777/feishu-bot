param(
    [switch]$NoPause
)

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CmdFile = Join-Path $ProjectDir "feishu_bot_autostart.cmd"
$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$ValueName = "FeishuBotAutoStart"
$CommandValue = "`"$CmdFile`""

if (-not (Test-Path $CmdFile)) {
    Write-Host "Missing file: $CmdFile"
    if (-not $NoPause) { Pause }
    exit 1
}

New-Item -Path $RunKey -Force | Out-Null
Set-ItemProperty -Path $RunKey -Name $ValueName -Value $CommandValue

Write-Host "Auto-start installed in registry."
Write-Host "Run key: $RunKey"
Write-Host "Value: $ValueName"
if (-not $NoPause) { Pause }
