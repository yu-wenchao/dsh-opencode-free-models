# dsh-opencode-free-models

DeepSeek Harness 插件：在聊天界面里实时展示 **OpenCode Zen** 的最新免费模型，并支持「一键置入」到 DSH 模型选择器，无需任何用户密钥即可使用。

免费模型统一使用字面量密钥 `"public"`（由宿主在加载时注入到环境变量 `OPENCODE_ZEN_API_KEY`），因此用户不必填写自己的 API Key。

## 功能

- 右下角浮动按钮唤起面板（抽屉式），关掉后状态记忆在 `localStorage`。
- 分页浏览免费模型，每页可配置（默认 20）。
- 单模型「一键置入 / 取消置入」，以及「⚡ 配置本页全部」批量操作。
- 「🔄 刷新」拉取最新列表，「⬆ 升级」检查后端版本。
- 后端不可达时给出友好提示，并提示站长在后台配置 CORS 白名单。
- 若宿主未暴露自动写入钩子，则回退为可复制的 YAML 片段，手动加入 `settings.yaml` 即可。

## 安装

将本包放入 DSH 的 web 配置目录（通过 cordis patch 注册，见 `cordis.patch.yml`）。宿主侧 `lib/index.js` 会：

1. 用 `normalizeConfig` 规整配置；
2. 注入 `OPENCODE_ZEN_API_KEY=public`（若环境变量未设置）；
3. 可选地在设置页注册 `opencode-free-models` 配置区块（依赖 `@deepseek-ai/schemastery` 与 `@deepseek-ai/dsh-settings`，缺失时自动跳过）。

浏览器侧 `lib/client.cjs` 自包含，无需构建步骤。

## 后端 API 约定

面板通过以下接口拉取数据（域名根由用户在面板内填写，存于 `localStorage`）：

### `GET /api/free-models?page=<n>&page_size=<m>`

返回：

```json
{
  "ok": true,
  "total": 42,
  "total_pages": 3,
  "page": 1,
  "page_size": 20,
  "items": [
    {
      "id": 1,
      "title": "模型名",
      "api_base_url": "https://opencode.ai/zen/v1",
      "model_name": ["model-id-1", "model-id-2"],
      "status": "enabled",
      "disabled_reason": "",
      "inserted": false
    }
  ]
}
```

- `status` 为 `"disabled"` 时展示「已下架」徽标，并提供 `disabled_reason`。
- 任何字段缺失或畸形的行都会被客户端静默丢弃，不会中断渲染。

### `GET /api/version`

返回 `{ "version": "0.1.0" }`，供面板「升级」按钮比对。

## 一键置入原理

每个免费模型会被转换成一个 `llm-pi-ai` 提供方条目：

```yaml
llm-pi-ai:
  providers:
    opencode-<slug>-<id>:
      apiKeyEnv: OPENCODE_ZEN_API_KEY
      api: openai-completions
      baseURL: "<api_base_url>"
      compat:
        supportsDeveloperRole: false
        maxTokensField: max_tokens
      models:
        - id: "<model-id>"
```

置入时，面板优先调用宿主钩子 `window.__OZF_HOST__.writeProvider(pid, entry)`；若宿主未提供该钩子，则弹出上述 YAML 供复制。

## 管理后台

- **总开关**：控制面板是否出现（通过 `cordis.patch.yml` / 设置区块）。
- **单模型使用期限 / 隐藏下架**：由后端 `status` 与 `disabled_reason` 驱动展示，前端只读。
- **CORS**：若面板持续报网络错误，请在后端「系统设置 → CORS 白名单」加入面板所在页面地址。

## 开发

```bash
node --test      # 运行测试，并校验 lib/client.cjs 内联 helper 与 lib/core.js 一致
```

`lib/core.js` 是共享 helper 的唯一真相来源；`lib/client.cjs` 内联了一份 **完全相同、标注 DO NOT EDIT** 的副本，`test/plugin.test.js` 会断言两者输出一致，防止漂移。
