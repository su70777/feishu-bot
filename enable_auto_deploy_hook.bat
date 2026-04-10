@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0enable_auto_deploy_hook.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %EXIT_CODE%

