@echo off
rem Launches Renamr without a console window (no install needed).
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Renamr.ps1"
