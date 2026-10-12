@echo off
chcp 65001 >nul
uv run reinstall.py
if exist "%~dp0..\l4d2-settings\설정_적용.cmd" call "%~dp0..\l4d2-settings\설정_적용.cmd"
pause
