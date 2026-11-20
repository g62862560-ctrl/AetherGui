@echo off
setlocal
cd /d "%~dp0"
call flutter build apk --debug --target-platform android-arm64
exit /b %errorlevel%
