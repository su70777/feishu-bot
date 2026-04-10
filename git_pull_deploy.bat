@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0git_pull_deploy.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %EXIT_CODE%
