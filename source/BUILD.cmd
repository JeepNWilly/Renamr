@echo off
rem Rebuilds ..\Renamr.ps1 and ..\Renamr.exe from these sources.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_exe.ps1" %*
pause
