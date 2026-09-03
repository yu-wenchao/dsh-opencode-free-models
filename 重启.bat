@echo off
chcp 65001 >nul
title 重启 DeepSeek Harness (dsh-opencode-free-models)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart.ps1"

