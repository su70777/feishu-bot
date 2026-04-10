@echo off
cd /d "%~dp0"
powershell -NoProfile -Command "Start-Process python -WorkingDirectory '%~dp0' -ArgumentList '-m','uvicorn','app:app','--host','127.0.0.1','--port','8000'"
powershell -NoProfile -Command "Start-Process cloudflared -ArgumentList 'tunnel','run','feishu-bot'"
echo Named tunnel start commands sent.
pause
