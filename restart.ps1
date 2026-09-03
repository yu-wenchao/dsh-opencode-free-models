<#
  dsh-opencode-free-models - 重启脚本
  关闭 DeepSeek Harness 进程，再启动你选中的那个（同 install/uninstall 的探测逻辑）。
  用法：双击 重启.bat，或 powershell -ExecutionPolicy Bypass -File restart.ps1 [-DSHHome <路径>]
#>
param([string]$DSHHome)

$ErrorActionPreference = 'Stop'

$PluginName = 'dsh-opencode-free-models'
$script:homes = @()
function Add-Home($h) {
    if ($h -and (Test-Path $h) -and (Test-Path (Join-Path $h 'profiles')) -and ($script:homes -notcontains $h)) {
        $profiles = Join-Path $h 'profiles'
        if ((Test-Path (Join-Path $profiles 'web')) -or (Test-Path (Join-Path $profiles 'desktop'))) {
            $script:homes += $h
        }
    }
}
Add-Home $env:DSH_HOME
if ($DSHHome -and (Test-Path $DSHHome)) { Add-Home $DSHHome }
Add-Home (Join-Path $HOME '.dsh')
$cur = $ScriptDir
for ($i = 0; $i -lt 6; $i++) {
    if ($cur -and (Test-Path $cur)) {
        if ((Test-Path (Join-Path $cur 'profiles\web')) -or (Test-Path (Join-Path $cur 'profiles\desktop'))) { Add-Home $cur }
        $parent = Split-Path $cur
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    } else { break }
}
$drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }
foreach ($d in $drives) {
    $root = $d.RootDirectory.FullName
    try {
        $job = Start-Job -ScriptBlock { param($r) Get-ChildItem -Path $r -Depth 1 -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and (Test-Path (Join-Path $_.FullName 'profiles')) } | ForEach-Object { $_.FullName } } -ArgumentList $root
        if (Wait-Job $job -Timeout 10) {
            $found = Receive-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            foreach ($f in $found) { Add-Home $f }
        } else {
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Write-Warn "跳过 $root （扫描超时）"
        }
    } catch { }
}

if ($script:homes.Count -eq 0) {
    Write-Host '未找到任何 DeepSeek Harness，请手动打开。'
    Read-Host '按回车键退出'
    exit 1
}

$selected = @()
if ($script:homes.Count -eq 1) {
    $selected = $script:homes
} else {
    Write-Host "发现 $($script:homes.Count) 个 DeepSeek Harness，请选择要重启的目录"
    for ($i = 0; $i -lt $script:homes.Count; $i++) {
        Write-Host ("  [$i] " + $script:homes[$i])
    }
    Write-Host '  [a] 全部重启'
    $ans = Read-Host '请输入编号（多个用逗号分隔，或 a 重启全部）'
    if ($ans -match 'a') {
        $selected = $script:homes
    } else {
        foreach ($tok in ($ans -split ',' | ForEach-Object { $_.Trim() })) {
            if ($tok -match '^\d+$') {
                $idx = [int]$tok
                if ($idx -ge 0 -and $idx -lt $script:homes.Count) { $selected += $script:homes[$idx] }
            }
        }
    }
}
if ($selected.Count -eq 0) {
    Write-Host '未选择任何目录，退出。'
    Read-Host '按回车键退出'
    exit 0
}

Write-Host '正在关闭 DeepSeek Harness ...'
try { taskkill /IM 'DeepSeekHarness.exe' /F 2>$null } catch { }
Start-Sleep -Seconds 1

foreach ($h in $selected) {
    $rootDir = Split-Path $h
    $exe = $null
    if (Test-Path (Join-Path $rootDir 'DeepSeekHarness.exe')) {
        $exe = Join-Path $rootDir 'DeepSeekHarness.exe'
    } else {
        $exe = Get-ChildItem $rootDir -Filter 'DeepSeekHarness.exe' -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $exe) {
        Write-Host "未找到该 harness 的 DeepSeekHarness.exe，跳过：$h"
        continue
    }
    Write-Host "正在启动：$exe"
    Start-Process $exe
}
Write-Host '完成。重启后插件生效。'
Read-Host '按回车键关闭'
