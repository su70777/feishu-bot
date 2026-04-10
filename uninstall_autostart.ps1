param(
    [switch]$NoPause
)

$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$ValueName = "FeishuBotAutoStart"

if ((Get-ItemProperty -Path $RunKey -Name $ValueName -ErrorAction SilentlyContinue)) {
    Remove-ItemProperty -Path $RunKey -Name $ValueName
    Write-Host "Auto-start removed from registry."
} else {
    Write-Host "Auto-start was not installed."
}

if (-not $NoPause) { Pause }
