@echo off
chcp 65001 >nul
title 安装 dsh-opencode-free-models
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
