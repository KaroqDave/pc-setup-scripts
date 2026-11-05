@echo off
rem Double-click to run the setup. It asks for admin rights.
rem Options can be added, for example:  windows-setup.cmd -check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows-setup.ps1" %*
if /i "%~1"=="-check" pause
if /i "%~1"=="-guide" pause
