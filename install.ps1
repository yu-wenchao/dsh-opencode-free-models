<#
  dsh-opencode-free-models - 一键安装脚本
  ======================================
  自动探测本机 DeepSeek Harness (DSH) 安装位置（桌面版 exe / npm 版 / 自托管 web 均覆盖），
  把「OpenCode 免费模型」插件复制进对应 profile 的 node_modules 并写入 package.json 登记。

  用法：
    双击 install.bat，或在 PowerShell 里运行：
      powershell -ExecutionPolicy Bypass -File install.ps1
#>

param([string]$DSHHome)

$ErrorActionPreference = 'Stop'
trap {
    Write-Err "安装过程中发生未捕获的错误: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Read-Host '按回车键关闭'
    exit 1
}
$Host.UI.RawUI.WindowTitle = 'dsh-opencode-free-models 一键安装'

$PluginName = 'dsh-opencode-free-models'
$ScriptDir  = $PSScriptRoot
$PluginSrc  = Join-Path $ScriptDir "plugin\$PluginName"

function Write-Step($msg) {
    Write-Host ''
    Write-Host ("[步骤] " + $msg) -ForegroundColor Cyan
}
function Write-Ok($msg) {
    Write-Host ("  [OK] " + $msg) -ForegroundColor Green
}
function Write-Warn($msg) {
    Write-Host ("  [注意] " + $msg) -ForegroundColor Yellow
}
function Write-Err($msg) {
    Write-Host ("  [错误] " + $msg) -ForegroundColor Red
}

function Test-PluginPackage {
    $pkgJson = Join-Path $PluginSrc 'package.json'
    if (-not (Test-Path $pkgJson)) { return $false }
    try {
        $pkg = Get-Content $pkgJson -Raw -Encoding utf8 | ConvertFrom-Json
        if ($pkg.name -ne $PluginName) { return $false }
        if (-not $pkg.dsh.bundle.patch) { return $false }
        if (-not (Test-Path (Join-Path $PluginSrc ($pkg.dsh.bundle.patch)))) { return $false }
        return $true
    } catch { return $false }
}

function Copy-PluginToNodeModules {
    param($Dest)
    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    Copy-Item -Recurse -Force $PluginSrc $Dest
    Remove-Item -Recurse -Force (Join-Path $Dest 'node_modules') -ErrorAction SilentlyContinue
}

function Install-IntoProfile {
    param($ProfileDir)
    $nodeModules = Join-Path $ProfileDir 'node_modules'
    $pkgJsonPath = Join-Path $ProfileDir 'package.json'
    if (-not (Test-Path $nodeModules)) {
        New-Item -ItemType Directory -Force -Path $nodeModules | Out-Null
        Write-Warn "profile 缺少 node_modules，已自动创建: $nodeModules"
    }
    if (-not (Test-Path $pkgJsonPath)) {
        Write-Warn "profile 缺少 package.json，跳过: $ProfileDir"
        return $false
    }

    # 1) 复制插件包到 node_modules
    $target = Join-Path $nodeModules $PluginName
    try {
        Copy-PluginToNodeModules -Dest $target
    } catch {
        Write-Err "复制插件包失败: $_"
        return $false
    }

    # 2) 注册到 package.json 的 dependencies + dsh.profile.bundles
    try {
        $json = Get-Content $pkgJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
        $changed = $false

        if (-not $json.dependencies) { $json | Add-Member -NotePropertyName 'dependencies' -NotePropertyValue (New-Object PSObject) -Force }
        $depObj = $json.dependencies
        if ($depObj -is [System.Collections.Hashtable]) {
            if (-not $depObj.ContainsKey($PluginName)) {
                $ver = (Get-Content (Join-Path $target 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json).version
                $depObj[$PluginName] = "file:$(Resolve-Path $PluginSrc)"
                $changed = $true
            }
        } else {
            if (-not $depObj.$PluginName) {
                $ver = (Get-Content (Join-Path $target 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json).version
                $depObj | Add-Member -NotePropertyName $PluginName -NotePropertyValue "file:$(Resolve-Path $PluginSrc)" -Force
                $changed = $true
            }
        }

        if (-not $json.dsh) { $json | Add-Member -NotePropertyName 'dsh' -NotePropertyValue @{} -Force }
        if (-not $json.dsh.profile) { $json.dsh | Add-Member -NotePropertyName 'profile' -NotePropertyValue @{} -Force }
        if (-not $json.dsh.profile.bundles) { $json.dsh.profile | Add-Member -NotePropertyName 'bundles' -NotePropertyValue @() -Force }
        $bundles = @($json.dsh.profile.bundles | ForEach-Object { $_ })
        if ($bundles -notcontains $PluginName) { $bundles += $PluginName; $changed = $true }
        $json.dsh.profile.bundles = $bundles

        if ($changed) {
            $jsonStr = $json | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($pkgJsonPath, $jsonStr, (New-Object System.Text.UTF8Encoding($false)))
            Write-Ok "已在 package.json 注册 (dependencies + dsh.profile.bundles)"
        } else {
            Write-Ok "package.json 已包含该插件，无需改动"
        }
        return $true
    } catch {
        Write-Err "修改 package.json 失败: $_"
        return $false
    }
}

# 探测：仅接受“包含 profiles 目录”的目录作为 DSH home
$script:homes = @()
function Add-Home($h) {
    if ($h -and (Test-Path $h) -and (Test-Path (Join-Path $h 'profiles')) -and ($script:homes -notcontains $h)) {
        # 必须是真 harness：profiles 下至少有 web 或 desktop 子配置档
        $profiles = Join-Path $h 'profiles'
        if ((Test-Path (Join-Path $profiles 'web')) -or (Test-Path (Join-Path $profiles 'desktop'))) {
            $script:homes += $h
        }
    }
}

Write-Host ''
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host '  dsh-opencode-free-models 一键安装' -ForegroundColor Magenta
Write-Host '  OpenCode Zen 免费模型面板 · DSH 社区插件' -ForegroundColor Magenta
Write-Host '==============================================' -ForegroundColor Magenta

# 0) 校验随包自带的插件包
Write-Step '检查安装包内容'
if (-not (Test-Path $PluginSrc)) {
    Write-Err "找不到插件包目录: $PluginSrc"
    Write-Err '请把整个文件夹（install.bat + plugin 文件夹）放在一起，不要拆开。'
    Read-Host '按回车键退出'
    exit 1
}
if (-not (Test-PluginPackage)) {
    Write-Err '插件包校验失败（缺少 package.json / lib 或 dsh.bundle.patch 配置）。'
    Read-Host '按回车键退出'
    exit 1
}
Write-Ok '安装包完整'

# 1) 探测 DSH 安装位置
Write-Step '正在探测本机 DeepSeek Harness 安装位置...'
Add-Home $env:DSH_HOME
if ($DSHHome -and (Test-Path $DSHHome)) { Add-Home $DSHHome }
Add-Home (Join-Path $HOME '.dsh')
# 若安装包被直接解压进 harness 目录内，自动用其所在位置
$cur = $ScriptDir
for ($i = 0; $i -lt 6; $i++) {
    if ($cur -and (Test-Path $cur)) {
        if ((Test-Path (Join-Path $cur 'profiles')) -and ((Test-Path (Join-Path $cur 'profiles\web')) -or (Test-Path (Join-Path $cur 'profiles\desktop')))) {
            Add-Home $cur
        }
        $parent = Split-Path $cur
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    } else { break }
}
# 自动探测：各盘根目录下含 profiles 的目录（快速，覆盖任意命名 harness，不再慢扫全盘）
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
    Write-Err '没有找到 DeepSeek Harness 的安装位置。'
    Write-Err '请确认已安装 DeepSeek Harness，或设置环境变量 DSH_HOME 指向其根目录（含 profiles 文件夹）。'
    Read-Host '按回车键退出'
    exit 1
}
foreach ($h in $script:homes) { Write-Ok "发现 DSH: $h" }

# 始终让用户自己选要装到哪个（不自动装，避免误装）
$selected = @()
Write-Step "发现 $($script:homes.Count) 个 DeepSeek Harness，请选择要安装到的目录"
for ($i = 0; $i -lt $script:homes.Count; $i++) {
    Write-Host ("  [$i] " + $script:homes[$i])
}
Write-Host '  [a] 全部安装'
$ans = Read-Host '请输入编号（多个用逗号分隔，或 a 安装全部）'
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
if ($selected.Count -eq 0) { Write-Warn '未选择任何目录，退出。'; Read-Host '按回车键退出'; exit 0 }

# 2) 遍历所选 DSH 的 profiles，安装插件
$installedAny = $false
foreach ($h in $selected) {
    $profilesRoot = Join-Path $h 'profiles'
    Write-Step "处理 DSH ($h) 的 profiles"
    $profiles = Get-ChildItem $profilesRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'node_modules' }
    if (-not $profiles) { Write-Warn "  没有发现 profile 目录: $profilesRoot" }
    foreach ($p in $profiles) {
        Write-Host ("  安装到 profile: " + $p.Name)
        $ok = Install-IntoProfile -ProfileDir $p.FullName
        if ($ok) { $installedAny = $true }
    }
    # 兜底：DSH 常把依赖 hoist 到 profiles 级共享 node_modules，补装一份
    $sharedNm = Join-Path $profilesRoot 'node_modules'
    if (-not (Test-Path $sharedNm)) { New-Item -ItemType Directory -Force -Path $sharedNm | Out-Null }
    try {
        Copy-PluginToNodeModules -Dest (Join-Path $sharedNm $PluginName)
        Write-Ok "已补装到共享 node_modules: $sharedNm"
        $installedAny = $true
    } catch {
        Write-Warn ("共享 node_modules 补装失败（可忽略）: " + $_.Exception.Message)
    }
}

# 3) 结果
Write-Step '安装结果'
if ($installedAny) {
    Write-Ok '插件已安装！重启 DeepSeek Harness 后，左侧边缘会出现 🎁 免费模型 按钮。'
    Write-Ok '步骤：1) 完全关闭并重新打开 DeepSeek Harness'
    Write-Ok '      2) 点左侧 🎁 打开「免费模型」面板'
    Write-Ok '      3) 免费模型已自动出现在输入框右下角的「模型」选择框，直接选用即可（无需密钥、无需置入）'
} else {
    Write-Warn '没有成功安装到任何 profile。请检查上面的提示。'
    Write-Warn '也可手动把「plugin\dsh-opencode-free-models」文件夹复制到'
    Write-Warn '  <DSH_HOME>\profiles\<名字>\node_modules\ 下，并在该 profile 的'
    Write-Warn '  package.json 的 dsh.profile.bundles 里加上 dsh-opencode-free-models。'
}

# 4) 可选：立即重启 harness，让插件立即生效
#    OpenCode 在启动时加载 bundle；安装只是放入文件 + 登记，不会热加载到运行中的会话，必须重启进程。
Write-Step '是否立即重启 DeepSeek Harness 让插件生效？'
$yn = Read-Host '重启 harness 以加载插件？(Y/n，默认 Y)'
if ($yn -notmatch '^n') {
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
        if ($exe) { Write-Ok "已启动：$exe"; Start-Process $exe } else { Write-Warn "未找到 $h 下的 DeepSeekHarness.exe，请手动打开 harness。" }
    }
    Write-Ok '已尝试重启，重新进入 harness 后插件（左侧 🎁 按钮）应已生效。'
} else {
    Write-Warn '未重启：请手动完全关闭并重新打开 DeepSeek Harness 后，插件才会生效。'
}

Write-Host ''
Read-Host '安装完成，按回车键关闭'

