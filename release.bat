@echo off
setlocal
if "%~1"=="" (
  echo Usage: release.bat X.Y.Z
  exit /b 1
)

set "BASH=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=C:\Program Files\Git\usr\bin\bash.exe"
if not exist "%BASH%" (
  echo Git Bash not found. Install Git for Windows.
  exit /b 1
)

set "ROOT=%~dp0"
set "ROOT=/%ROOT:~0,1%%ROOT:~2%"
set "ROOT=%ROOT:\=/%"

"%BASH%" -lc "cd '%ROOT%' && ./release.sh %1"
exit /b %errorlevel%
