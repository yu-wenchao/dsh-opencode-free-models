// dsh-opencode-free-models · OpenCode Zen 免 key provider (host side)
//
// 本文件在宿主(Node)侧实现一个完整的 LLM adapter，让用户不用登录、不用 key，
// 就能通过 OpenCode Zen 的免费档使用免费模型。认证使用字面量 key "public"
// （OpenCode Zen 官方免费档，无需注册）。
//
// 参考 dsh-opencode-zen（MIT）的机制，但这里是独立实现、使用独立的 provider
// 名 "opencode-free"，因此与 dsh-opencode-zen 的 "opencode" 互不冲突：
//   - 用户只装本插件 → 出现 "opencode-free" provider 的免费模型
//   - 用户同时装了 dsh-opencode-zen → "opencode" 与 "opencode-free" 各自独立
//
// 注册模型后，模型会出现在「输入框右下角的模型选择器」，并且当本插件被
// 后台暂停/卸载时，模型会随之全部失效（registerAdapter 的清理机制）。

export const PROVIDER = 'opencode-free'
export const OPENCODE_BASE = 'https://opencode.ai/zen/v1'
// Mimic the official opencode client so the free tier's rate-limiter treats us
// the same way (dsh-opencode-zen uses this identical UA and hits 429 far less).
const OPENCODE_UA = 'opencode/1.18.18 ai-sdk/provider-utils/4.0.23 runtime/bun/1.3.14'
const DEFAULT_MAX_TOKENS = 128000
const DEFAULT_CONTEXT_WINDOW = 200000
const MAX_REQUEST_ATTEMPTS = 2

// OpenCode Zen 免费模型（与官方免费档一致）。provider 名统一为 "opencode-free"。
export const MODELS = [
  { id: 'big-pickle', name: 'Big Pickle (Free)', contextWindow: 200000, description: 'OpenCode Zen 免费档' },
  { id: 'mimo-v2.5-free', name: 'MiMo 2.5 (Free)', contextWindow: 200000, description: 'OpenCode Zen 免费档' },
  { id: 'hy3-free', name: 'Hunyuan 3 (Free)', contextWindow: 200000, description: 'OpenCode Zen 免费档（腾讯混元）' },
  { id: 'nemotron-3-ultra-free', name: 'Nemotron 3 Ultra (Free)', contextWindow: 131072, description: 'OpenCode Zen 免费档（NVIDIA）' },
  { id: 'nemotron-3.5-lightning-free', name: 'Nemotron 3.5 Lightning (Free)', contextWindow: 131072, description: 'OpenCode Zen 免费档（NVIDIA）' },
  { id: 'muse-spark-1.2-contributor-free', name: 'Muse Spark 1.2 Contributor (Free)', contextWindow: 200000, description: 'OpenCode Zen 免费档（贡献者）' },
].map((m) => ({ ...m, provider: PROVIDER }))

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

// Shared literal key by default; an operator can raise the free-tier ceiling by
// exporting OPENCODE_ZEN_API_KEY (or OPENCODE_GO_API_KEY) with a real key.
// Same fallback order as dsh-opencode-zen.
function resolveApiKey() {
  return process.env.OPENCODE_ZEN_API_KEY
    || process.env.OPENCODE_GO_API_KEY
    || 'public'
}

function flattenText(content) {
  if (Array.isArray(content)) return content.filter((b) => b.type === 'text').map((b) => b.text).join('')
  return typeof content === 'string' ? content : ''
}

function blocksOf(content, type) {
  return Array.isArray(content) ? content.filter((b) => b.type === type) : []
}

/** DSH/Harness 消息 → OpenAI chat.completions wire 格式。 */
function serializeMessages(messages, systemPrompt) {
  const wire = []
  if (systemPrompt) wire.push({ role: 'system', content: systemPrompt })
  for (const m of messages || []) {
    const role = m.role
    if (role === 'system') {
      wire.push({ role: 'system', content: flattenText(m.content) })
      continue
    }
    if (role === 'assistant') {
      const text = flattenText(m.content)
      const reasoning = blocksOf(m.content, 'reasoning').map((b) => b.text).join('')
      const toolCalls = blocksOf(m.content, 'tool-call').map((b) => ({
        id: b.id, type: 'function', function: { name: b.name, arguments: b.arguments },
      }))
      const msg = { role: 'assistant', content: text }
      if (reasoning) msg.reasoning_content = reasoning
      if (toolCalls.length) msg.tool_calls = toolCalls
      wire.push(msg)
      continue
    }
    const toolResults = blocksOf(m.content, 'tool-result')
    const text = flattenText(m.content)
    if (text || toolResults.length === 0) wire.push({ role: 'user', content: text })
    for (const r of toolResults) {
      wire.push({ role: 'tool', tool_call_id: r.toolCallId, content: flattenText(r.content) || '(no output)' })
    }
  }
  return wire
}

function serializeTools(tools) {
  if (!tools || tools.length === 0) return undefined
  return tools.map((t) => ({
    type: 'function',
    function: { name: t.name, description: t.description, parameters: t.parameters },
  }))
}

/** SSE 逐行解析，产出 OpenAI 流式 chunk。 */
async function* parseSse(response) {
  const reader = response.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      buffer += decoder.decode(value, { stream: true })
      let idx
      while ((idx = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, idx).trim()
        buffer = buffer.slice(idx + 1)
        if (!line.startsWith('data:')) continue
        const data = line.slice(5).trim()
        if (!data) continue
        if (data === '[DONE]') return
        try { yield JSON.parse(data) } catch { /* 忽略坏行 */ }
      }
    }
  } finally {
    reader.releaseLock()
  }
}

/** OpenAI usage → DSH 期望的 token 字段（数字，杜绝 NaN 写进会话历史）。 */
function mapUsage(usage) {
  const cacheRead = usage?.prompt_tokens_details?.cached_tokens || 0
  return {
    inputTokens: (usage?.prompt_tokens || 0) - (cacheRead || 0),
    outputTokens: usage?.completion_tokens || 0,
    ...(cacheRead ? { cacheReadTokens: cacheRead } : {}),
  }
}

/** OpenAI 流式 chunk → DSH 需要的块事件。 */
async function* translateStream(rawChunks, estimateInput) {
  let nextIndex = 0
  let textBlock = null
  let reasoningBlock = null
  const toolBlocks = new Map()
  const order = []
  let finish = null
  let usage = null

  const open = (kind) => {
    const block = { index: nextIndex++, kind, text: '' }
    order.push(block)
    return block
  }

  for await (const chunk of rawChunks) {
    const choices = chunk.choices || []
    for (const choice of choices) {
      const delta = choice.delta || {}
      const rc = delta.reasoning_content
      if (typeof rc === 'string' && rc.length > 0) {
        if (!reasoningBlock) {
          reasoningBlock = open('reasoning')
          yield { type: 'block-start', index: reasoningBlock.index, blockType: 'reasoning' }
        }
        reasoningBlock.text += rc
        yield { type: 'reasoning-delta', index: reasoningBlock.index, text: rc }
      }
      const content = delta.content
      if (typeof content === 'string' && content.length > 0) {
        if (!textBlock) {
          textBlock = open('text')
          yield { type: 'block-start', index: textBlock.index, blockType: 'text' }
        }
        textBlock.text += content
        yield { type: 'text-delta', index: textBlock.index, text: content }
      }
      for (const call of delta.tool_calls || []) {
        const bIdx = call.index || 0
        let block = toolBlocks.get(bIdx)
        if (!block) {
          block = open('tool-call')
          toolBlocks.set(bIdx, block)
          yield { type: 'block-start', index: block.index, blockType: 'tool-call' }
        }
        const fn = call.function || {}
        if (call.id) block.callId = call.id
        if (fn.name) block.name = fn.name
        if (fn.arguments) {
          block.text += fn.arguments
          yield { type: 'tool-call-delta', index: block.index, name: block.name || '', argumentsDelta: fn.arguments }
        }
      }
      if (chunk.finish_reason === 'length') finish = { kind: 'max-tokens' }
    }
    if (chunk.usage) usage = mapUsage(chunk.usage)
  }

  for (const block of order) {
    switch (block.kind) {
      case 'text': yield { type: 'block-end', index: block.index, block: { type: 'text', text: block.text } }; break
      case 'reasoning': yield { type: 'block-end', index: block.index, block: { type: 'reasoning', text: block.text } }; break
      case 'tool-call':
        yield {
          type: 'block-end',
          index: block.index,
          block: { type: 'tool-call', id: block.callId || '', name: block.name || '', arguments: block.text },
        }
        break
    }
  }

  if (!usage && estimateInput) {
    const inputText = estimateInput()
    usage = {
      inputTokens: Math.ceil(inputText.length / 4),
      outputTokens: (textBlock?.text || '').length > 0 ? Math.ceil(textBlock.text.length / 4) : 0,
    }
  }
  yield { type: 'usage', usage }
  yield { type: 'finish', reason: finish || { kind: 'stop' } }
}

/**
 * 免 key OpenCode Zen adapter。结构参考 dsh-opencode-zen（MIT），但精简并
 * 使用独立的 "opencode-free" provider 名。认证固定为 `Bearer public`。
 */
export class OpenCodeFreeAdapter {
  constructor(ctx, control) {
    this.ctx = ctx
    this.control = control || { enabled: () => true }
    // 活的模型集。初始为官方基座 MODELS；后端轮询到最新列表后用 setModels()
    // 重建：新模型进、废弃（后端已下架）模型出。listModels/resolveModel 均读它。
    this.models = MODELS
  }
  get paused() {
    try { return this.control.enabled ? !this.control.enabled() : false } catch { return false }
  }
  /** 用后端 /api/models 的有效模型集替换当前模型集（注入到输入框容器）。 */
  setModels(list) {
    if (!Array.isArray(list) || list.length === 0) return
    this.models = list.map((m) => ({
      provider: PROVIDER,
      id: m.id,
      name: m.name || m.id,
      description: m.description || '',
    }))
  }
  providerInfo(provider) {
    return { id: provider, name: 'OpenCode Zen Free' }
  }
  providerRetryPolicy() {
    return {
      mode: 'normal',
      maxRetries: 2,
      retryableCodes: ['RATE_LIMITED', 'TIMEOUT', 'TRANSPORT'],
      backoff: { initialDelayMs: 800, maxDelayMs: 5000, jitterRatio: 0.1 },
    }
  }
  listModels() {
    // 暂停时返回空列表：模型从「模型选择器」消失。
    if (this.paused) return Promise.resolve([])
    const models = Array.isArray(this.models) ? this.models : MODELS
    return Promise.resolve(models.map((m) => ({ provider: PROVIDER, id: m.id, name: m.name, description: m.description, inputModalities: ['text'] })))
  }
  resolveModel(provider, model) {
    const models = Array.isArray(this.models) ? this.models : MODELS
    const found = models.find((m) => m.id === model)
    return Promise.resolve({
      provider: PROVIDER,
      id: model,
      name: found?.name || model,
      ...(found?.description ? { description: found.description } : {}),
      inputModalities: ['text'],
      context: { contextWindow: found?.contextWindow || DEFAULT_CONTEXT_WINDOW },
      defaultMaxTokens: DEFAULT_MAX_TOKENS,
    })
  }

  async *stream(options) {
    // 暂停屏障：插件被暂停时拒绝一切请求，任何已选该模型的消息都无法回复。
    if (this.paused) {
      const err = new Error('OpenCode Zen Free is paused: enable it in the plugin settings to use these models')
      err.code = 'PAUSED'
      err.paused = true
      throw err
    }
    const { model, messages, system, tools, maxTokens, temperature, signal } = options
    const wireMessages = serializeMessages(messages, system)
    const wireTools = serializeTools(tools)

    const body = {
      model,
      messages: wireMessages,
      stream: true,
      stream_options: { include_usage: true },
      max_tokens: maxTokens || DEFAULT_MAX_TOKENS,
      top_p: 0.95,
      ...(temperature !== undefined ? { temperature } : {}),
      ...(wireTools ? { tools: wireTools, tool_choice: 'auto' } : {}),
    }

    let lastError = null
    for (let attempt = 0; attempt < MAX_REQUEST_ATTEMPTS; attempt++) {
      if (signal?.aborted) throw aborted()
      try {
        const controller = new AbortController()
        const timer = setTimeout(() => controller.abort(), options.timeoutMs || 60000)
        const onAbort = () => controller.abort()
        if (signal) signal.addEventListener('abort', onAbort)

        let response
        try {
          response = await fetch(`${OPENCODE_BASE}/chat/completions`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${resolveApiKey()}`,
              'User-Agent': OPENCODE_UA,
            },
            body: JSON.stringify(body),
            signal: controller.signal,
          })
        } finally {
          clearTimeout(timer)
          if (signal) signal.removeEventListener('abort', onAbort)
        }

        if (!response.ok) {
          const raw = await response.text().catch(() => '')
          const code = response.status === 429 ? 'RATE_LIMITED' : response.status >= 500 ? 'TRANSPORT' : 'PROVIDER_ERROR'
          lastError = new Error(`OpenCode Zen HTTP ${response.status}: ${raw.slice(0, 300)}`)
          lastError.code = code
          if (code !== 'RATE_LIMITED' && code !== 'TRANSPORT') throw lastError
          await sleep(400 * (attempt + 1))
          continue
        }

        yield* translateStream(parseSse(response), () => JSON.stringify(wireMessages))
        return
      } catch (err) {
        if (signal?.aborted) throw aborted()
        if (err.name === 'AbortError' && !options.timeoutMs) throw err
        lastError = err
        if (attempt < MAX_REQUEST_ATTEMPTS - 1) await sleep(400 * (attempt + 1))
      }
    }
    throw lastError || new Error('OpenCode Zen request failed')
  }
}

function aborted() {
  const e = new Error('OpenCode Zen request aborted by caller')
  e.code = 'ABORTED'
  return e
}

/** 在 DSH 的 llm 服务里注册 opencode-free provider（免 key）。
 *  @param control 可选：{ enabled: () => boolean }，暂停时模型从选择器消失且无法回复。
 */
export function installOpenCodeFreeProvider(ctx, log, control) {
  if (typeof ctx.llm?.registerAdapter !== 'function') {
    if (typeof log === 'function') log('llm service unavailable; adapter not registered')
    return null
  }
  const adapter = new OpenCodeFreeAdapter(ctx, control)
  const handle = ctx.llm.registerAdapter([PROVIDER], adapter)
  // 暴露 adapter，便于 host 在轮询到最新后端列表后用 setModels() 重建模型集，
  // 再调 handle.replace(...) 触发 emit，让输入框容器随官方变化同步（新增/弃用）。
  handle.adapter = adapter
  if (typeof log === 'function') {
    log(`provider "${PROVIDER}" registered, ${adapter.models.length} free models (免 key, Bearer public)`)
  }
  return handle
}
