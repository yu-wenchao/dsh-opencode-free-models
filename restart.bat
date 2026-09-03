@echo off
chcp 65001 >nul
title restart DeepSeek Harness (dsh-opencode-free-models)
:: 重启 DSH 使插件生效。默认按进程名结束并重新启动（需在 PATH 或改成完整路径）。
:: 若你的 DSH 主程序不在 PATH 中，把下面改成完整路径，例如：
::   set "DSH_EXE=C:\Program Files\DeepSeekHarness\DeepSeekHarness.exe"
set "DSH_EXE=DeepSeekHarness.exe"

tasklist /fi "imagename eq %DSH_EXE%" | find /i "%DSH_EXE%" >nul
if errorlevel 1 (
    echo DeepSeek Harness 当前未运行。
) else (
    echo 正在关闭 DeepSeek Harness ...
    taskkill /IM "%DSH_EXE%" /F >nul 2>&1
    timeout /t 1 >nul
)
echo 正在启动 DeepSeek Harness ...
start "" "%DSH_EXE%" 2>nul || echo [提示] 无法自动启动 %DSH_EXE%，请手动打开 DeepSeek Harness。
echo 完成。
pause
