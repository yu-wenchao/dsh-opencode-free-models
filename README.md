# dsh-opencode-free-models  无限免费额度的deepseek harnes 免费模型插件

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)
[![Node.js >= 18](https://img.shields.io/badge/Node.js-%3E%3D18-brightgreen.svg)](https://nodejs.org)
[![DSH Plugin](https://img.shields.io/badge/DSH-Plugin-blue.svg)](https://github.com/deepseek-ai/deepseek-harness)

> **DeepSeek Harness (DSH) 插件** — 在聊天界面里实时展示 **OpenCode Zen** 的最新免费模型，**无需登录、无需密钥**，直接在模型选择器选用即可对话。

---

## 目录

- [这是什么](#这是什么)
- [核心特性](#核心特性)
- [工作原理](#工作原理)
- [项目结构](#项目结构)
- [小白安装教程](#小白安装教程)
  - [第一步：确认你已安装 DeepSeek Harness](#第一步确认你已安装-deepseek-harness)
  - [第二步：下载插件包](#第二步下载插件包)
  - [第三步：双击安装](#第三步双击安装)
  - [第四步：重启 DeepSeek Harness](#第四步重启-deepseek-harness)
  - [第五步：开始使用](#第五步开始使用)
- [手动安装（非 Windows / 服务器）](#手动安装非-windows--服务器)
- [从源码构建](#从源码构建)
- [配置说明](#配置说明)
- [后端 API](#后端-api)
- [架构详解](#架构详解)
- [安全说明](#安全说明)
- [常见问题](#常见问题)
- [无限额度使用技巧](#无限额度使用技巧)
- [卸载](#卸载)
- [开发指南](#开发指南)
- [许可证](#许可证)

---

## 这是什么

`dsh-opencode-free-models` 是一个 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 插件，它做的很简单：

1. 自动从后端拉取最新的 OpenCode Zen 免费模型列表
2. 把这些模型注册到 DSH 的模型选择器里
3. 你在输入框右下角直接选择模型就能对话

**你不需要做任何额外操作** —— 装完插件，重启 DSH，免费模型就自动出现在模型选择器里了。

---

## 核心特性

- **零配置** — 安装即用，无需登录、无需 API Key
- **自动同步** — 模型列表自动从后端拉取，官方新增自动出现、弃用自动消失
- **双端支持** — 同时支持 DSH 桌面端和 Web 端
- **一键安装** — Windows 用户双击 `install.bat` 即可
- **安全可靠** — 无密钥收集、XSS 防护、fail-closed 授权
- **后台可控** — 站长可通过后端控制总开关、单模型上下架、可用时间窗

---

## 工作原理

```
┌─────────────────────────────────────────────────────────┐
│                    DeepSeek Harness                      │
│  ┌──────────────┐    ┌──────────────────────────────┐   │
│  │  模型选择器   │◄───│  opencode-free provider       │   │
│  │  (输入框右下) │    │  (宿主侧 adapter 注册)        │   │
│  └──────────────┘    └──────────────┬───────────────┘   │
│                                     │                    │
│  ┌──────────────┐    ┌──────────────▼───────────────┐   │
│  │ 🎁 免费模型   │    │  轮询后端 /api/models (30s)   │   │
│  │  面板 (抽屉)  │    │  获取最新模型列表             │   │
│  └──────────────┘    └──────────────┬───────────────┘   │
└─────────────────────────────────────┼────────────────────┘
                                      │
                          ┌───────────▼───────────┐
                          │   后端 API 服务        │
                          │   (站长维护)           │
                          │   free-api.gd7.cn     │
                          └───────────────────────┘
```

### 数据流

1. **插件加载** → 宿主半（`index.js`）向 DSH 的 `llm` 服务注册 `opencode-free` provider
2. **轮询同步** → 每 30 秒从后端 `/api/models` 拉取最新模型列表，更新模型选择器
3. **用户对话** → 选择 `opencode-free/*` 模型 → 请求发送到 `opencode.ai/zen/v1` → SSE 流式返回
4. **暂停/恢复** → 后端关闭总开关 → provider 路由被移除 → 模型从选择器消失

### 认证方式

所有免费模型使用共享字面量密钥 `Bearer public`，由宿主在加载时自动注入环境变量 `OPENCODE_ZEN_API_KEY=public`。用户无需也不应填写任何 Key。

---

## 项目结构

```
dsh-opencode-free-models/
├── src/                          # 开发源码
│   ├── index.js                  # 宿主半（Node 侧）：注册 provider、轮询开关、跨进程授权桥
│   ├── provider.js               # OpenCode Zen 免 key 适配器：SSE 解析、流式转换、模型管理
│   ├── core.js                   # 纯函数：配置校验、URL 安全化、模型列表解析、YAML 生成
│   └── client/
│       └── index.js              # 浏览器半：面板 UI、分页、授权交互、XSS 防护
│
├── lib/                          # 运行时产物（由 build.mjs 从 src/ 原样复制）
│   ├── index.js                  # 宿主半
│   ├── provider.js               # 适配器
│   ├── core.js                   # 核心 helper
│   └── client.cjs                # 浏览器面板（CJS bundle）
│
├── one-click-install/            # 一键安装包（Windows 用户用）
│   ├── install.bat               # 安装/更新
│   ├── restart.bat               # 重启 DSH
│   ├── install.ps1               # PowerShell 安装脚本（核心逻辑）
│   ├── restart.ps1               # PowerShell 重启脚本
│   └── plugin/
│       └── dsh-opencode-free-models/
│           ├── package.json      # 插件元数据
│           ├── cordis.patch.yml  # DSH 补丁配置（后端地址、分页等）
│           ├── lib/              # 插件运行时文件（安装时复制到 DSH）
│           ├── README.md
│           └── LICENSE
│
├── scripts/
│   └── build.mjs                 # 构建脚本：src/ → lib/ + one-click-install
│
├── test/
│   ├── plugin.test.js            # 验收测试：core + provider + host + client
│   └── auth.test.mjs             # 授权流程测试
│
├── patches/                      # 可选补丁（仅特殊环境使用，正常安装无需）
├── docs/                         # 详细文档（架构、内部实现、运维手册）
├── package.json                  # 项目元数据
├── cordis.patch.yml              # DSH bundle 层补丁
├── DSH-PLUGIN-ARCHITECTURE.md    # 完整架构文档（对照 DSH 源码核验）
├── INSTALL.md                    # 安装说明
└── LICENSE                       # MIT 许可证
```

### 源码 vs 运行时

| 目录 | 用途 | 说明 |
|------|------|------|
| `src/` | 开发源码 | 宿主半、适配器、核心 helper、浏览器面板 |
| `lib/` | 运行时 | 由 `build.mjs` 从 `src/` 原样复制，与 DSH 运行中插件字节一致 |
| `one-click-install/plugin/` | 发布包 | 安装时复制到 DSH 的 `node_modules` |

---

## 小白安装教程

> **预计用时：2 分钟**  
> **适用系统：Windows 10/11**  
> **前提：已安装 DeepSeek Harness**

### 第一步：确认你已安装 DeepSeek Harness

DeepSeek Harness 是一个 AI 助手工具，本插件需要在它里面运行。

如果你还没有安装，请先到 [DeepSeek Harness 官网](https://github.com/deepseek-ai/deepseek-harness) 下载安装。

### 第二步：下载插件包

从本页面的 [Releases](https://github.com/yu-wenchao/dsh-opencode-free-models/releases) 下载最新版本的发布包。

或者直接克隆本仓库：

```bash
git clone https://github.com/yu-wenchao/dsh-opencode-free-models.git
```

下载后解压，你会看到一个 `one-click-install` 文件夹。

### 第三步：双击安装

1. 打开 `one-click-install` 文件夹
2. **双击 `install.bat`**（或 `安装.bat`）

脚本会自动：
- 探测你电脑上 DeepSeek Harness 的安装位置
- 把插件复制到正确的位置
- 在 `package.json` 中注册插件

安装过程中会提示你选择要安装到哪个 DSH 目录（如果你有多个），输入编号即可。

> **如果脚本提示"没有找到 DeepSeek Harness"**  
> 请确认你已安装 DeepSeek Harness，或设置环境变量 `DSH_HOME` 指向 DSH 根目录（包含 `profiles` 文件夹的那个目录）。

### 第四步：重启 DeepSeek Harness

安装完成后，脚本会询问是否立即重启。选择 **Y** 即可。

如果没有选择自动重启，请：
1. 完全关闭 DeepSeek Harness（包括系统托盘里的图标）
2. 重新打开 DeepSeek Harness

### 第五步：开始使用

重启后，你会看到：

1. **左侧边缘** 出现一个绿色的 **🎁 免费模型** 按钮
2. **输入框右下角** 的模型选择器里自动出现了 `opencode-free/*` 系列模型

直接选择任意 `opencode-free` 模型，就可以开始免费对话了！

---

## 手动安装（非 Windows / 服务器）

如果你使用 macOS / Linux，或者需要在服务器上安装：

### 方法一：使用一键安装脚本（推荐）

```bash
# 克隆仓库
git clone https://github.com/yu-wenchao/dsh-opencode-free-models.git
cd dsh-opencode-free-models

# 运行安装脚本
node scripts/build.mjs  # 构建 lib/
```

然后把 `one-click-install/plugin/dsh-opencode-free-models/` 文件夹手动复制到 DSH 的插件目录：

```
<DSH_HOME>/profiles/web/node_modules/dsh-opencode-free-models/
```

### 方法二：完全手动

1. 把 `one-click-install/plugin/dsh-opencode-free-models/` 整个文件夹复制到：
   ```
   <DSH_HOME>/profiles/web/node_modules/dsh-opencode-free-models/
   ```

2. 编辑该 profile 的 `package.json`，添加两处：
   ```json
   {
     "dependencies": {
       "dsh-opencode-free-models": "0.1.0"
     },
     "dsh": {
       "profile": {
         "bundles": ["dsh-opencode-free-models"]
       }
     }
   }
   ```

3. 重启 DSH

> **找不到 DSH 目录？**  
> 桌面端常见位置：
> - Windows: `C:\Users\你的用户名\AppData\Roaming\DeepSeekHarness\`
> - macOS: `~/Library/Application Support/DeepSeekHarness/`
> - Linux: `~/.config/DeepSeekHarness/`

---

## 从源码构建

需要 Node.js >= 18。

```bash
# 克隆仓库
git clone https://github.com/yu-wenchao/dsh-opencode-free-models.git
cd dsh-opencode-free-models

# 构建（把 src/ 原样复制到 lib/ 和 one-click-install/）
node scripts/build.mjs

# 验证构建产物与源码一致
node scripts/build.mjs --check

# 运行测试
node --test test/plugin.test.js
```

---

## 配置说明

插件配置通过 `cordis.patch.yml` 或 DSH 设置界面管理。

### 默认配置

```yaml
# cordis.patch.yml（bundle 层）
- insert:
    - id: opencode-free-models
      name: dsh-opencode-free-models
      config:
        backendUrl: 'https://free-api.gd7.cn/opencode'  # 后端地址
        pageSize: 20                    # 每页模型数
        requestTimeoutMs: 10000         # 请求超时（毫秒）
        uiSlot: ''                      # UI 挂载位置（空=右侧抽屉）
        providerIdPrefix: opencode      # Provider ID 前缀
        footerLinks:                    # 面板底部链接
          - label: 技术笔记
            url: http://blog.4wc.cn
          - label: 插件开发
            url: https://blog.gd7.cn/
        debug: false                    # 调试日志
```

### 自定义后端

如果你有自己的后端服务：

1. 修改 `cordis.patch.yml` 中的 `backendUrl`
2. 或在 DSH 设置界面的插件配置中修改

### 分层覆盖

DSH 支持多层配置覆盖（后层优先）：

```
bundle 层（cordis.patch.yml）  ←  你在这里
    ↓
profile 层（profiles/web/cordis.patch.yml）
    ↓
home 层（$DSH_HOME/cordis.patch.yml）
```

---

## 后端 API

插件通过以下接口与后端通信：

### GET /api/models

获取模型列表。

```json
{
  "ok": true,
  "total": 42,
  "total_pages": 3,
  "page": 1,
  "page_size": 20,
  "opencode_enabled": true,
  "items": [
    {
      "id": 1,
      "title": "模型名",
      "api_base_url": "https://opencode.ai/zen/v1",
      "model_name": ["model-id-1", "model-id-2"],
      "status": "enabled",
      "usable": true,
      "available_from": "2025-01-01 00:00:00",
      "available_until": "2025-12-31 23:59:59"
    }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `opencode_enabled` | 全局总开关，`false` 时所有模型不可用 |
| `items[].status` | `disabled` 时该模型显示"已下架" |
| `items[].usable` | `false` 时该模型不可用 |
| `items[].available_from/until` | 可用时间窗 |

### GET /api/version

检查后端版本。

```json
{ "version": "0.1.0" }
```

### GET /api/articles

获取公告/文章列表。

### GET /api/license?act=status

获取授权状态。

```json
{ "auth_enabled": false }
```

---

## 架构详解

### 双进程架构

插件分为两个独立部分：

| 部分 | 文件 | 运行环境 | 职责 |
|------|------|----------|------|
| 宿主半 | `lib/index.js` | Node.js（DSH 进程） | 注册 provider、轮询开关、跨进程授权桥 |
| 浏览器半 | `lib/client.cjs` | 浏览器（WebView） | 面板 UI、分页、授权交互 |

两者通过本机 HTTP 桥（`127.0.0.1:18766`）跨进程通信。

### Provider 注册

```
ctx.llm.registerAdapter(['opencode-free'], adapter)
    │
    ├── listModels()     → 返回免费模型列表
    ├── resolveModel()   → 返回模型详情
    └── stream()         → SSE 流式对话
```

### 开关机制

插件有三层开关，取交集：

1. **本地开关** (`localEnabled`) — DSH 设置界面的插件开关
2. **远程开关** (`remoteEnabled`) — 后端 `/api/models` 的 `opencode_enabled`
3. **授权门禁** (`authRequired && !authorized`) — 后端要求授权但用户未授权

任一关闭 → `providerHandle.replace([])` → 模型从选择器消失。

### 跨进程授权桥

浏览器半（授权弹窗）→ HTTP POST `127.0.0.1:18766/ozf-auth` → 宿主半（更新授权状态）

默认 fail-closed：未收到授权信号时隐藏模型。

---

## 安全说明

- **无密钥收集** — 使用共享公共密钥 `public`，用户无需也不应填写任何 Key
- **XSS 防护** — `innerHTML` 经 `sanitizeHtml()` 剥离危险标签/事件属性/`javascript:`
- **URL 校验** — `safeHttpUrl()` 仅放行绝对 `http(s)` 协议
- **授权 fail-closed** — 默认 `authorized=false`，后端要求授权时未收到信号即隐藏模型
- **credentials: 'omit'** — 面板 fetch 请求不携带 Cookie

---

## 常见问题

| 现象 | 可能原因 | 解决方法 |
|------|----------|----------|
| 左侧没有 🎁 按钮 | 插件未安装或未重启 | 确认 `lib/client.cjs` 存在，重启 DSH |
| 面板一直"加载中" | 后端不可达或 CORS 未配置 | 检查网络；让站长在后端 CORS 白名单加入 DSH 页面地址 |
| 模型在选择器不出现 | 后端总开关关闭或插件被禁用 | 检查后端 `opencode_enabled`；检查 `cordis.patch.yml` 是否 `disabled: true` |
| 模型出现但发送被拒 | 后端要求授权但未授权 | 在面板中完成授权；或让站长关闭 `auth_enabled` |
| 升级按钮失败 | 网络/CORS 问题 | 可忽略，不影响使用 |

---

## 无限额度使用技巧

> **核心原理：免费额度按网络 IP 分配，切换网络 = 重置额度 = 无限免费使用！**

### 为什么会出现 429？

OpenCode Zen 的免费模型**通过网络 IP 限制每日额度**。当你看到 `429 Rate Limited` 错误时：

- **不是**传统意义上的"限流"（请求太频繁）
- **而是**你当前网络 IP 的**每日免费额度已用完**

### 如何实现无限额度？

准备**多个网络**，额度用完就切换，每个新 IP 都有全新的每日免费额度：

| 网络来源 | 切换方式 | 额度重置 |
|----------|----------|----------|
| 手机热点 | 关闭 → 重新开启热点 | 新 IP = 新额度 |
| 随身 WiFi | 重启设备或切换 SIM 卡 | 新 IP = 新额度 |
| 家庭宽带 | 重启路由器（部分运营商会换 IP） | 可能新 IP = 新额度 |
| 公司/学校网络 | 切换到手机热点 | 新 IP = 新额度 |
| VPN | 切换不同地区节点 | 新 IP = 新额度 |

### 推荐操作流程

```
1. 正常使用免费额度
2. 遇到 429 错误 → 额度用完了
3. 切换网络（如：关闭 WiFi → 开启手机热点）
4. 继续使用 → 又有新的免费额度了！
5. 重复以上步骤 = 无限免费额度
```

### 实用技巧

- **手机热点是最方便的方式** — 随时随地切换，无需额外设备
- **随身 WiFi 适合重度用户** — 插入 SIM 卡即可获得独立 IP
- **多准备 2-3 个网络源** — 足够覆盖一天的使用量
- **不需要重启 DSH** — 切换网络后直接继续对话，插件会自动使用新 IP 的额度
- **桌面端和 Web 端都适用** — 只要网络切换了，额度就重置了

---

## 卸载

### Windows（推荐）

双击 `one-click-install/restart.bat` 或 `重启.bat`，然后删除插件目录。

### 手动

1. 删除插件目录：
   ```
   <DSH_HOME>/profiles/web/node_modules/dsh-opencode-free-models/
   <DSH_HOME>/profiles/desktop/node_modules/dsh-opencode-free-models/  # 桌面端
   ```

2. 从该 profile 的 `package.json` 中移除：
   - `dependencies` 中的 `"dsh-opencode-free-models"`
   - `dsh.profile.bundles` 中的 `"dsh-opencode-free-models"`

3. 重启 DSH

---

## 开发指南

### 开发环境

```bash
# 安装依赖（无外部依赖，仅 Node.js >= 18）
node --version  # 确认 >= 18

# 运行测试
node --test test/plugin.test.js

# 构建
node scripts/build.mjs

# 验证一致性
node scripts/build.mjs --check
```

### 源码修改流程

1. 编辑 `src/` 下的源文件
2. 运行 `node scripts/build.mjs` 同步到 `lib/` 和 `one-click-install/`
3. 运行 `node --test test/plugin.test.js` 验证
4. 重启 DSH 测试

### 关键文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/index.js` | 372 | 宿主半入口：provider 注册、开关轮询、授权桥 |
| `src/provider.js` | 367 | OpenCode Zen 适配器：SSE 解析、流式转换 |
| `src/core.js` | 258 | 纯函数：配置校验、URL 安全化 |
| `src/client/index.js` | 1674 | 浏览器面板：UI 渲染、授权交互 |

---

## 许可证

[MIT](./LICENSE)

---

## 致谢

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) — LLM 宿主运行时
- [OpenCode Zen](https://opencode.ai) — 免费模型 API
