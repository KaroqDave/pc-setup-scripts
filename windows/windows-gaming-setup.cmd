@echo off
rem Double-click to run the gaming setup. It asks for admin rights.
rem Options can be added, for example:  windows-gaming-setup.cmd -Check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows-gaming-setup.ps1" %*
if /i "%~1"=="-Check" pause
if /i "%~1"=="-Guide" pause
