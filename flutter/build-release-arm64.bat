@echo off
setlocal
cd /d "%~dp0"
call flutter pub get --enforce-lockfile
if errorlevel 1 exit /b %errorlevel%
call flutter analyze
if errorlevel 1 exit /b %errorlevel%
call flutter test
if errorlevel 1 exit /b %errorlevel%
call flutter build apk --release --target-platform android-arm64
if errorlevel 1 exit /b %errorlevel%
call powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\report-apk.ps1" -ApkPath "%~dp0build\app\outputs\flutter-apk\app-release.apk"
exit /b %errorlevel%
