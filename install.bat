@echo off
PowerShell -ExecutionPolicy Bypass -NoProfile -Command "Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File ""%~dp0install.ps1""' -Verb RunAs"
