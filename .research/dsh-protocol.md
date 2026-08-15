# DSH Desktop —— 浏览器↔宿主 RPC 协议、token 用量数据、活动会话判定（只读研究文档）

> 实测环境：宿主服务器运行于 `http://127.0.0.1:3080`（本机 dsh webtest profile）。
> npm 包源码：`/Users/iiiiiei/.npm/_npx/1e7f6d9597241db0/node_modules/@deepseek-ai/`
> 本文档所有 curl 示例均在上述服务器上实测通过（标注了实测响应）。
> 时间戳均为 epoch 毫秒（如 `1786796164902`）。

---

## 任务 1：浏览器 → 宿主的 RPC 调用协议

### 1.1 总体架构（两条载体 + 一条下行流）

| 载体 | 方法 | URL | 用途 |
|---|---|---|---|
| HTTP 单向 RPC（apiproxy full-form） | `POST` | `/api/<method>`（如 `/api/session.list`） | 会话管理、发消息、模型列表等一切"一问一答"调用 |
| HTTP 单向 RPC（Typert gateway，内部） | `POST` | `/api/<namespace>/<method>`（如 `/api/desktop/stats`，payload 为 `{args}`） | 宿主 Typert 远程方法；`dsh-api-gateway` 用拦截器抢占 `/api` 下 `ns/method` 形状的端点 |
| WebSocket 下行事件 | `ws://` 升级 | `/api/events.mux`、`/api/events.host` | 会话事件流（增量消息、approval、projection 更新等） |

三个关键源码文件：

- `dsh-client-connection/lib/index.js`：`/api` 前缀路由、**浏览器信任 fence**（`isTrustedApiRequest`）、HTTP↔fetch 桥、WebSocket 下行。
- `dsh-host-apiproxy/lib/index.js`：**方法注册表** `UNARY_ROUTES`（`session.list` / `session.create` / `session.prompt` / `session.history` / `llm.models` 等 50+ 方法）、request/response 的 zod schema、`toFetchHandler` 与 `AbstractApiClient`（浏览器侧的客户端协议实现）。
- `dsh-api-gateway/lib/index.js`：`TypertGatewayService` —— 对 `/api` 拦截器的 RPC dispatch（`dispatchRpc`），只认 payload `{args: {...}}`。

> **重要**：`session.*` 与 `llm.*` 走的是 **apiproxy full-form 信封**（见 1.2），不是 gateway 的 `{args}` 格式。gateway 只服务 `命名空间/方法`（斜杠分隔、两段）的 Typert 远程端点；`session.list` 这类带点号的方法名不是 gateway 端点，落到 apiproxy 兜底处理器。

### 1.2 信封格式（wire full-form，字段级）

请求（`clientRequestSchema`，来自 `dsh-host-apiproxy/lib/types/api/rpc.schema.js`）：

```json
{
  "type": "client-request",   // 字面量，唯一合法值
  "rpcId": "任意字符串",       // 不透明 echo 令牌；实测 "test-list-1" 即可（无需 UUID）
  "method": "session.list",   // 必须等于 URL 路径中的方法名，否则 bad-request
  "payload": {}               // 每方法的业务参数（schema 二次校验）
}
```

响应（`serverResponseSchema`）：

```json
{
  "type": "server-response",        // 字面量
  "rpcId": "与请求完全一致",          // 客户端校验回显，不一致会抛错
  "result": {
    "ok": true,
    "value": { ... }                 // 业务成功值（每个方法有自己的 value schema）
  }
  // 或
  "result": {
    "ok": false,
    "error": {
      "code": "session-not-found",   // 见 1.6 错误码表
      "message": "session \"xxx\" not found",
      "details": { "sessionId": "xxx" }
    }
  }
}
```

**HTTP 状态码只表达载体层**：业务错误永远是 `HTTP 200 + result.ok:false`。
非 200 的含义：`403` fence 拒绝；`404` 未知路径/方法；`415` Content-Type 不是 `application/json`；`400` body 不是 JSON 或缺 Host；`413` body 超限（默认上限 160 MiB，`maxRequestBodyBytes`）；`426` 对 `/api/events.mux` 走普通 HTTP GET（要求 WebSocket 升级）；`500` 处理器崩溃。

请求头（实测必须项）：

| 头 | 值 | 说明 |
|---|---|---|
| `Content-Type` | `application/json` | 缺失/其它 → 415 |
| `Host` | `127.0.0.1:3080` | fence 权威校验，见 1.5 |
| `Origin` | 缺省即可（桌面/curl） | 浏览器会带；必须与 Host 同源 |
| `Sec-Fetch-Site` | 不得为 `cross-site` | 浏览器自动带 |

### 1.3 实测 curl 示例（可直接照抄）

**① session.list（列出会话，含每个会话的 token 投影！）**

```bash
curl -sS -X POST http://127.0.0.1:3080/api/session.list \
  -H 'Content-Type: application/json' \
  -d '{"type":"client-request","rpcId":"list-1","method":"session.list","payload":{}}'
```

实测响应（节选，`result.value.items` 为数组，按 `updatedAt` 降序）：

```json
{"type":"server-response","rpcId":"list-1","result":{"ok":true,"value":{"items":[
  {"sessionId":"8862c85e-7b71-4345-ad96-772ef521a79e","updatedAt":1786796164902,
   "running":true,"blank":false,"parentSessionId":"session-a09c087f-...","origin":"subagent",
   "cwd":"/Users/iiiiiei/Desktop","agentPreset":"cordis",
   "projections":{"asOfSeq":4553,"values":{
     "tokenUsage":{"uncachedInputTokens":49672,"outputTokens":5049,"cacheReadTokens":324736,"cacheWriteTokens":0},
     "contextPressure":{"pressureTokens":53448,"projectedTokens":55037,"contextWindow":1000000},
     "contextBreakdown":{"systemTokens":4504,"toolsTokens":8438,"messageTokens":35579},
     "sessionStats":{"turns":1,"steps":11,...},"title":"...","goal":null,
     "subagent":{"mode":"continuable","label":"..."},
     "sessionListMetadata":{"blank":false,"lastPromptAt":1786796164902},
     "imageLimits":{...},"todos":[...],"plan":{...},
     "permissions":{...},"subagentTiming":{...}}}}
]}}}
```

**② session.create（拿到新会话 id）**

```bash
curl -sS -X POST http://127.0.0.1:3080/api/session.create \
  -H 'Content-Type: application/json' \
  -d '{"type":"client-request","rpcId":"create-1","method":"session.create",
       "payload":{"cwd":"/Users/iiiiiei/Desktop","agentPreset":"cordis"}}'
```

实测响应：`{"type":"server-response","rpcId":"create-1","result":{"ok":true,"value":{"sessionId":"session-807d9c60-c191-4763-a113-0d3e130fc970","agentPreset":"cordis"}}}`

`payload` 可选字段：`cwd`（字符串）与 `workspaceId`（字符串）**二选一**（同时给 → `bad-request`，实测：`{"code":"bad-request","message":"invalid payload for session.create","details":{"issues":[{"message":"session.create accepts workspaceId or cwd, not both"}]}}`）；还支持 `sessionId`（自定义 id）、`agentPreset`。

**③ session.prompt（发消息）—— 非流式！**

```bash
SID=session-807d9c60-c191-4763-a113-0d3e130fc970
curl -sS -X POST http://127.0.0.1:3080/api/session.prompt \
  -H 'Content-Type: application/json' \
  -d "{\"type\":\"client-request\",\"rpcId\":\"prompt-1\",\"method\":\"session.prompt\",
       \"payload\":{\"sessionId\":\"$SID\",\"mode\":\"queue\",
                    \"content\":[{\"type\":\"text\",\"text\":\"你好\"}]}}"
```

实测响应（**非流式**，立即返回受理确认，不含回复文本）：

```json
{"type":"server-response","rpcId":"prompt-1","result":{"ok":true,"value":{"accepted":true}}}
```

**assistant 回复文本不在 prompt 响应里**，走两条路任选：

- **实时**：`ws://127.0.0.1:3080/api/events.mux` 下行帧（见 1.7），事件类型 `assistant/chunk`（`data.chunk` = `text-delta` / `reasoning-delta` / `block-start` / `block-end` / `usage` / `finish`）与最终的 `assistant/message`（`data.message.content` 数组里 `type:"text"` 的块即完整回复）。
- **事后**：`session.history`（见 1.4）读 `assistant/message` 事件。实测：发送"你好"后 history 中 seq 136 为
  `{"type":"assistant/message","seq":136,"time":...,"data":{"turn":1,"step":1,"message":{"role":"assistant","content":[{"type":"reasoning","text":"..."},{"type":"text","text":"你好！我是运行在 DeepSeek Harness 上的编程智能体。..."}]},"usage":{"inputTokens":6217,"outputTokens":117,"cacheReadTokens":5888,"reasoningTokens":43}}}`

`session.prompt` payload schema：`sessionId`(必填)、`mode` = `"queue"` | `"steer"`、`content` = 数组（`{"type":"text","text":string}` 或 `{"type":"image","mediaType":"image/png|jpeg|webp|gif","data":<base64>,"name"?}`）、`clientTimeZone`(可选)。
响应：`{accepted: true}`，若首字符为斜杠命令则多一个 `command: {kind:"success", text?}`。
错误：会话不存在 → `{"code":"session-not-found","details":{"sessionId":"..."}}`（实测）。

**④ llm.models（模型目录，确认可用）**

```bash
curl -sS -X POST http://127.0.0.1:3080/api/llm.models \
  -H 'Content-Type: application/json' \
  -d '{"type":"client-request","rpcId":"llm-1","method":"llm.models","payload":{}}'
```

实测响应（value 结构）：

```json
{"ok":true,"value":{"groups":[
  {"id":"deepseek-official","name":"DeepSeek",
   "models":[
     {"id":"deepseek-v4-flash","name":"DeepSeek-V4-Flash",
      "reasoning":{"efforts":[{"id":"off","name":"Off"},{"id":"high","name":"High"},{"id":"max","name":"Max"}],"defaultEffort":"high"}},
     {"id":"deepseek-v4-pro","name":"DeepSeek-V4-Pro","reasoning":{...}}]}
],"failures":[]}}
```

### 1.4 字段级 schema（核心方法）

**session.list**
- 请求 `sessionListRequestSchema`：`{ cursor?: string }`（cursor 为 v1 预留座位，未实现，可不传）
- 响应 `sessionListValueSchema`：`{ items: SessionSummary[] }`
- `SessionSummary`：
  - `sessionId: string`（必填）
  - `updatedAt: number`（epoch ms，= `max(header.createdAt, 最近一次人工 user/message 的 time)`，见 1.8）
  - `running: boolean`（该会话的 agent 此刻是否在执行轮次，见任务 3）
  - `blank: boolean`（尚无用户消息的空会话）
  - `parentSessionId?: string`、`origin?: "subagent"`、`cwd?: string`、`agentPreset?: string`
  - `projections?: { asOfSeq: number, values: Record<string, unknown> }`（每个注册投影 key 一个 value，见任务 2）
- 排序：`items.sort((a,b) => b.updatedAt - a.updatedAt)`（源码 2255 行，最新在前）

**session.create**
- 请求：`{ workspaceId?: string, cwd?: string, sessionId?: string, agentPreset?: string }`，`workspaceId` 与 `cwd` 互斥（refine 校验）
- 响应：`{ sessionId: string, agentPreset?: string }`

**session.history**
- 请求：`{ sessionId: string, beforeSeq?: number, maxMessages?: number }`（从窗口尾部向前翻页）
- 响应：`{ events: HistoryEntry[], hasMore: boolean, projections?: {asOfSeq, values} }`
- `HistoryEntry` = `{ event: SessionEvent, view?: {for:"call"|"result", view: {...}} }`
- `SessionEvent` 严格信封 + 宽 data：`{ type: string, seq: number(>=0), time: number, data: unknown, sourceEventSeqs?: number[], surfaceOp?: unknown, ignorable?: true }`
- 关键事件类型（实测）：`user/message`（data: `{content:[{type:"text",text}], role:"user", id, source:{kind,...}}`）、`assistant/chunk`、`assistant/message`、`request/header`、`request/context`、`step/start|end`、`turn/start|end`、`session/title`、`tool/call`、`tool/result`、`compaction/summary|prune`、`permission/preset` 等。

**session.prompt** —— 见 1.3 ③。

**llm.models** —— 见 1.3 ④。`groups[].models[].reasoning.efforts[]` 为 `{id,name,description?}`。

**错误体**（`rpcErrorSchema` 的 code 全集）：`bad-request`、`cancelled`、`session-not-found`、`model-unavailable`、`session-conflict`、`invalid-time-zone`、`workspace-*`、`directory-*`、`agent-preset-*`、`agent-busy`、`attachment-error`、`queue-item-not-found`、`steer-unavailable`、`command-error`、`unknown-command`、`settings-*`、`credential-rejected`、`model-discovery-failed`、`title-invalid`、`fork-unavailable`、`subagent-*`、`internal`。details 必填，结构随 code 变化（如 `session-not-found` → `{sessionId}`）。

### 1.5 浏览器信任 fence（`isTrustedApiRequest`，源码 dsh-client-connection 184–198 行）

判定顺序（全部满足才放行）：

1. `Host` 头必须存在且可解析（无 Host → HTTP 400，实测）。
2. Host 主机名必须是 **loopback**（`localhost`、`[::1]`、`127/8` 任意地址）**或** 命中配置 `trustedHosts`（`client-connection` 插件配置，默认 `[]`，条目为 `host[:port]`，无端口条目匹配任意端口）。否则 → 403。
3. `Sec-Fetch-Site: cross-site` → 403（浏览器跨站请求）。
4. 若带 `Origin`：其 host 必须与 Host 头同源，否则 403。**无 Origin 头直接放行**。

**实测矩阵**（全部针对 `POST /api/llm.models`）：

| 场景 | Host 头 | 附加头 | 结果 |
|---|---|---|---|
| 默认 curl（桌面应用等价） | `127.0.0.1:3080` | 无 | **200 ✓** |
| `Host: localhost:3080` | `localhost:3080` | 无 | **200 ✓** |
| 恶意域名 | `evil.com` | 无 | **403** `forbidden` |
| 浏览器同源 | `127.0.0.1:3080` | `Origin: http://127.0.0.1:3080` | **200 ✓** |
| 跨源 | `127.0.0.1:3080` | `Origin: https://evil.example` | **403** `forbidden` |
| 跨站标记 | `127.0.0.1:3080` | `Sec-Fetch-Site: cross-site` | **403** `forbidden` |
| 无 Host | — | `Host:` 置空 | **400**（HTTP 层） |
| GET（非 POST） | `127.0.0.1:3080` | — | **404** `not found` |

**桌面应用结论**：Swift `URLSession` / `curl` 是非浏览器客户端，不发 `Origin`、`Sec-Fetch-Site`；只要 `Host: 127.0.0.1:3080`（loopback）即可通过 fence，**无需任何 token/密钥**。WebSocket 升级同样过同一 fence（实测 `ws://127.0.0.1:3080/api/events.mux` 直连成功）。

**豁免/绕过**：fence 只认 loopback 与 `trustedHosts`；`trustedHosts` 是 `cordis.yml` 里 `client-connection` 插件配置（如 `["192.168.1.5:3080"]` 允许 LAN IP）。注意 `PRIVILEGED_METHODS`（`agentPreset.*`、`settings.*`、`credentials.*`、`host.pickDirectory/openPath`、`llm.discoverModels` 等，源码 504–520 行）即使部署了 `trustedHosts` 也**强制 loopback-only**——`session.*`、`llm.models`、`llm.providers`、`workspace.*`、`subagent.list` 等不在其列，LAN 也可用。**fence 是 DNS-rebinding/CSRF 防线，不是认证层**：任何能连到 3080 端口的本机进程都能调 `/api`。

### 1.6 方法注册表（`UNARY_ROUTES` 全集）

`session.list / search / create / history / models / selectModel / rename / fork / prompt / attachment / updateQueue / cancel`、`subagent.list / history / prompt / interrupt`、`host.describe / pickDirectory / listDirectory / createDirectory / openPath`、`workspace.list / create / rename / delete / insertBefore / insertSessionBefore / archiveSession`、`skill.list`、`agentPreset.list / select / read / copy / openDocument / remove`、`goal.create / edit / pause / resume / complete / clear`、`settings.describe / openDocument / update / replace / mutate`、`credentials.describe / set / unset`、`llm.providers / models / discoverModels`。
另有非 RPC 端点：`POST /api/respond`（approval/问题应答，`clientResponseSchema` 信封 `{type:"client-response",rpcId,result:{ok,value}}`）、`GET|HEAD /api/session.export?sessionId=...`（日志导出）。

### 1.7 事件下行（WebSocket，实时通道）

- URL：`ws://127.0.0.1:3080/api/events.mux`（mux 流）与 `ws://127.0.0.1:3080/api/events.host`（host 流）。
- **普通 HTTP GET 这两个路径返回 426 `upgrade required`**（实测）——client-connection 拦截了 SSE，实际只有 WebSocket 载体；升级握手同样过 fence。
- 每帧是 JSON 文本帧，`serverRequest` 全形：`{"type":"server-request","rpcId":"<uuid>","method":"<帧类型>","payload":{...}}`。
- mux 帧类型（`muxFrameSchema`）：`session/event`（`{sessionId, event, view?}`，**主要增量来源**）、`session/subscribed`、`approval/requested`、`approval/resolved`、`question/requested`、`question/resolved`、`session/queue`、`session/jobs`、`session/projection`（`{sessionId, key, value, seq}`，投影变更实时推送）、`stream/error`。
- host 帧类型：`host/session-added`、`host/session-removed`、`host/session-status`（`{sessionId, running}`）、`host/agent-error`、`host/workspace-*`、`host/archived-sessions-changed`、`host/remote-event`、`stream/error`。
- 实测：用 Node `ws` 客户端连接 mux，12 秒收到 **687 帧**，全是正在运行的会话的 `assistant/chunk` 增量（`{"type":"server-request","rpcId":"...","method":"session/event","payload":{"type":"session/event","sessionId":"session-a09c087f-...","event":{"type":"assistant/chunk","seq":244364,"time":1786796364187,"data":{"turn":9,"step":26,"chunk":{"type":"reasoning-delta","index":0,"text":"快速"}}}}}`）。客户端只收不发（上行一律走 HTTP POST）。

---

## 任务 2：token 用量数据读取

### 2.1 三个投影（dsh-token-meter/lib/index.js）

`TokenMeter` 服务（`ctx.tokenMeter`，无配置项）在 `ctx.inject(["sessionProjections"])` 里注册三个投影 unit。**投影值通过 `sessionProjections.snapshot(session).values` 或 `session.list` 的 `projections.values` 直接可读**（见实测 JSON）。

| key | view 结构（即投影值） | 数据来源 |
|---|---|---|
| `tokenUsage` | `{ uncachedInputTokens: int>=0, outputTokens: int>=0, cacheReadTokens: int>=0, cacheWriteTokens: int>=0 }`（严格 schema） | 事件 `assistant/chunk`（`chunk.type==="usage"`）与 `assistant/message`（`data.usage`）；按 `(turn,step)` 去重替换，同一步内新样本替换旧样本不重复计数；**累计值**，`view()` 直接返回 `state.totals` |
| `contextPressure` | `{ pressureTokens? , projectedTokens?, contextWindow? }`（均可选） | `pressureTokens = inputTokens + cacheRead + cacheWrite`（prompt 侧）；`contextWindow` 来自 `request/context` 事件；`projectedTokens = max(0, pressureTokens + surface 增量)` |
| `contextBreakdown` | `{ systemTokens: int>=0, toolsTokens: int>=0, messageTokens: int>=0 }` | `request/header` 事件（系统提示/工具 schema 按 `chars/4` 启发式估算）；`messageTokens` 走 O(1) surface 折叠 |

`tokenUsage` 内部状态（持久化的是这个，不是 view）：`{totals:{...四桶}, last:{turn, step, buckets:{...}} | null}`。`stateVersion`：tokenUsage=1、contextPressure=4、contextBreakdown=2。

**菜单栏取值**：uncached 输入 = `tokenUsage.uncachedInputTokens`，输出 = `tokenUsage.outputTokens`，缓存命中 = `tokenUsage.cacheReadTokens`，缓存写入（未命中写入） = `tokenUsage.cacheWriteTokens`。注意 `cacheWriteTokens` 在实测中恒为 0（DeepSeek 官方 API 不报 cache 写入量）；"缓存未命中"可用 `uncachedInputTokens + cacheWriteTokens` 表达。

### 2.2 持久化格式与位置（dsh-session-projection-cache + dsh-storage-json + dsh-storage-domain）

- 服务 `ctx.sessionProjectionCache`（`SessionProjectionCache`，inject `["storageDomain","sessionProjections","sessionPersistence","sessions"]`），把每个会话的投影检查点按 `(sessionId, key, ver, seq, val)` 落到 `session_projcache` 域。
- 域规范：`defineDomain({name:"session_projcache", version:3, tables:{sessions: domainTable(checkpointRecord)}})`。
- **文件**：`~/.dsh/storages/session_projcache.json`（`storage-json` 后端配置 `root: !!js dshHomePath('storages')`，见 `dsh-web-app/cordis.patch.yml` 54–62 行；路径规则 `<root>/<域名>.json`）。原子写：同目录临时文件 + fsync + rename。
- 文件格式（`serialize()`）：`{"unit":{"name":"session_projcache","version":3},"global":null,"tables":{"sessions":{ "<sessionId>": {...} }}}`，pretty-printed。
- 每条记录（`checkpointRecord`）：
  ```json
  {
    "identity": {"createdAt": 1786780897524, "cwd": "/Users/iiiiiei/Desktop"},   // 绑定日志生命周期，读时校验
    "rows": {
      "tokenUsage":     {"ver": 1, "seq": 245096, "val": {"totals": {"uncachedInputTokens": 527600, "outputTokens": 255144, "cacheReadTokens": 56628096, "cacheWriteTokens": 0}, "last": {...}}},
      "contextPressure":{"ver": 4, "seq": 245096, "val": {"surfaceTokens": ..., "pressureTokens": ..., "contextWindow": 1000000, ...}},
      "contextBreakdown":{"ver": 2, "seq": 245096, "val": {"systemTokens": 4399, "toolsTokens": 8247, "messageTokens": 264919}},
      "sessionStats":   {"ver": 1, "seq": 245096, "val": {"turns":9,"steps":294,...}},
      "title":          {"ver": 1, "seq": 245096, "val": "开发DeepSeek Harness的macOS应用"},
      "goal": {"ver":4,"seq":245096,"val":{...}},
      "sessionListMetadata": {"ver":1,"seq":245096,"val":{"blank":false,"lastPromptAt":1786795803393}},
      "permissions","imageLimits","todos","plan","subagent","subagentTiming" ...
    }
  }
  ```
- `seq` = 该行的投影水位（会话事件 seq，**不是时间戳**）；`ver` 与 unit 的 `stateVersion` 不匹配的行读时直接丢弃（缓存语义：宁可重放，绝不迁移）。
- 写路径：`session/event` 触发节流写（`writeEveryEvents` / `writeIntervalMs` 配置）+ 强制点 `turn/end` 与会话 dispose；`session/disposed` 清账。

### 2.3 storages / sessions 磁盘布局（实测 `~/.dsh`）

```
~/.dsh/
├── settings.yaml                     # 插件配置（agent-default-model 等）
├── .credentials.yaml
├── storages/                         # 域文件（storage-json root）
│   ├── session_projcache.json        # ← token 投影检查点（上文 2.2）
│   ├── workspace.json                # 工作区/会话归属
│   └── message_feedback.json
└── sessions/                         # 会话日志（dsh-session-persistence-jsonl）
    └── --Users-iiiiiei-Desktop--/    # 目录名 = cwd 的 `/` 替换为 `-` 并加 `--` 包裹
        └── <sessionId>/
            └── session.jsonl.zstd    # zstd 压缩 JSONL（实测 14966 行事件）
```

`session.jsonl.zstd` 格式（`zstd -d -c` 实测）：
- 第 1 行 = header：`{"type":"session","version":0,"id":"session-a09c087f-...","createdAt":1786780897524,"cwd":"/Users/iiiiiei/Desktop","delegationDepth":0,"agentPreset":"standard"}`
- 之后每行一个事件：`{"type":"permission/preset","seq":0,"time":1786780897641,"data":{...}}` —— **每个事件都有 `time`（epoch ms）**。

### 2.4 通过 RPC 读 usage：现成端点与宿主注入路径

- **没有** 专门的 `usage`/`projection` 查询端点。**现成渠道 = `session.list` 的 `projections.values.tokenUsage / contextPressure / contextBreakdown`**（每个会话一行，实测返回，零额外成本）。`session.history` 的尾部也带 `projections` 块。
- 宿主侧注入的服务（名字 + 方法签名，源码已验证）：
  - `ctx.sessionProjections`（`SessionProjectionRegistry`，dsh-session-projection）：`snapshot(session) → {asOfSeq, values}`（live，同步）、`checkpoint(session) → rows`、`viewCheckpoint(rows) → values`（冷读，零 I/O）、`restore(checkpoint, events, baseSeq) → {snapshot, checkpoint}`、`restoreFloor(checkpoint) → seq|undefined`、`onChanged(listener)`、`register(definition)`。
  - `ctx.sessions`（`SessionStore`，dsh-session）：`list() → Session[]`（live 会话，创建序）、`get(id)`。
  - `ctx.sessionProjectionCache`（dsh-session-projection-cache）：`cachedSnapshot(meta) → {asOfSeq, values}|undefined`（冷会话投影，零日志加载，identity 校验）、`coldSnapshot(id, signal)`（完整冷读）、`recordFor(id, expected)`。
  - `ctx.sessionPersistence`：`list(signal) → meta[]`（含 `{id, createdAt, cwd}`）、`readFrom(id, seq, signal) → {meta, events}`。
- 桥接插件完整代码见 **任务 5 之后的"桥接插件"章节**。

### 2.5 会话"最近活跃"字段

`session.list` 每行有 `updatedAt`（epoch ms）= `max(header.createdAt, 最后一次人工 user/message 的 time)`（源码 `sessionListUpdatedAt`，1267–1269 行）。另有 `running`（此刻在跑轮次）、`blank`、`projections.values.sessionListMetadata.lastPromptAt`（最近一次人工 prompt 的 time，可为 null）。没有 `lastActive`/`activity` 字段名——`updatedAt` 就是权威的"最近活跃"。

### 2.6 "按天聚合所有会话"可行性

- **投影值本身没有时间戳**（`tokenUsage` 只有累计四桶；`seq` 是事件序号）。`session_projcache.json` 的 `rows.*.seq` 无法换算日期。
- 可用的会话级时间戳：`session.list` 的 `updatedAt`、`projections.values.sessionListMetadata.lastPromptAt`、日志 header 的 `createdAt`、以及日志里每个事件的 `time`。
- 结论：**"按天聚合"只能做到"按会话的最后活跃日/创建日分组汇总累计值"**（用 `updatedAt`/`lastPromptAt` 的日期部分分组、把每个会话的 `tokenUsage` 累加），无法得到"某天的 token 增量"。
- 若要精确的每日增量：需直接读 `session.jsonl.zstd`（每个 `assistant/chunk` 的 `usage` 事件带 `time`），自己解压并 fold——或者等 `session/projection` 实时帧 + 自己记账。对菜单栏显示（今日累计）建议：用 `updatedAt`/`lastPromptAt` 落在今天的会话求和，或维护本地增量记账。

---

## 任务 3：当前打开会话的判定

- **宿主没有"窗口/当前打开会话"概念**：`session.list` 的响应字段里没有 `active`/`current`/`locked` 之类字段。`workspace.list` 的 `workspaceViewSchema` 只有 `sessionIds`（归属关系），也没有"聚焦"概念。"哪个会话的窗口开着"是纯客户端 UI 状态，不进 wire 协议。
- 宿主唯一能给的动态信号：
  - `running: boolean` —— 该会话的 agent 此刻是否正在执行轮次（源码 `summarizeAttached`：`agent?.status === "running"`；`dsh-agent-loop` 380–382 行：`get status() { return this.phase.kind === "idle" || this.phase.kind === "maintenance" ? "idle" : "running"; }`）。**`running:true` 表示"正在干活"，不等于"窗口开着"**。
  - `updatedAt` —— 最近活跃时间。
  - 事件流：`host/session-added`（`{sessionId, blank, parentSessionId?, cwd?, agentPreset?}`）、`host/session-removed`、`host/session-status`（`{sessionId, running}`）——可实时维护会话集合与运行态。
- **桌面应用建议**："当前会话"取 `running:true` 的会话（可能多个，如子 agent）；否则取 `updatedAt` 最大者。若目标是"菜单栏显示最近会话的 token"，直接按 `updatedAt` 降序取第一条即可（与 GUI 侧栏顺序一致）。

---

## 桌面应用（Swift URLSession）调用 /api 注意事项

1. **fence**：`URLSession` 默认不发 `Origin`/`Sec-Fetch-Site`，只要 `Host` 头是 `127.0.0.1:3080`（loopback）即放行。不要设置 `Host` 为其它值；如果走 `http://localhost:3080` 同样放行（`localhost` 是 loopback）。**不要**用 `URLSession` 的 `allowsCellularAccess` 之类——无需网络权限，本机回环即可。
2. **Headers**：`Content-Type: application/json`（必须）；无鉴权头；无 cookie。
3. **信封**：必须用 full-form `{type:"client-request",rpcId,method,payload}`；`method` 与 URL 路径一致；`rpcId` 任意字符串（建议 UUID）；校验响应 `rpcId` 回显；业务错误看 `result.ok === false`（HTTP 仍是 200）。
4. **超时**：浏览器客户端默认 30s（`DEFAULT_TIMEOUT_MS`，`AbortSignal.timeout(30000)`）；`session.prompt` 立即返回，长耗时在事件流/轮询里，所以 30s 足够。
5. **事件流**：用 `URLSessionWebSocketTask` 连 `ws://127.0.0.1:3080/api/events.mux`（Swift 的 `URLSessionWebSocketTask` 支持 ws:// 文本帧）。不要用 SSE（HTTP GET 该路径返回 426）。收到 `{"type":"server-request","method":"session/event",...}` 解析 `payload.event`。
6. **读取回复**：`session.prompt` 返回 `accepted:true` 后，要么订阅 mux 流直到该会话 `turn/end` 事件，要么轮询 `session.history`（`maxMessages` 取尾页）找 `assistant/message` 事件；其 `data.message.content` 中 `type==="text"` 块的 `text` 即最终回复。
7. **权限**：`session.*`、`llm.*` 不在特权方法列表，loopback 下可全量调用；若未来要调 `settings.*`/`credentials.*` 也仍是 loopback 放行（特权方法只是锁死 loopback，不额外鉴权）。

---

## 桥接插件：`/api/desktop/stats` 读取 token 投影（Cordis 宿主插件，注入 webServer）

### 方案：直接注册 exact 路由（推荐，URL 最干净）

关键点：`webServer.register()` 的匹配是 **exact 表优先、前缀表最长匹配兜底**（`dsh-host-webserver` 194–203 行）。`client-connection` 注册的是 `/api` 前缀路由；桥接插件注册 exact `/api/desktop/stats` 会**先于** `/api` 前缀命中，因此**不会经过 client-connection 的 fence**——插件必须自己复刻最小 fence（loopback Host 检查 + 拒绝跨站 Origin）。

服务注入（全部是宿主级服务，插件 `inject` 数组声明）：`webServer`（路由）、`sessions`（live 会话）、`sessionProjections`（live 投影快照）、`sessionProjectionCache`（冷会话投影，零日志加载）、`sessionPersistence`（冷会话元数据枚举）。`sessionProjections`/`sessionProjectionCache` 用 `ctx.get()` 可选读取更稳（它们由 token-meter / projection-cache 插件提供）。

```js
// cordis 宿主插件（动态 Cordis 插件或 preset 内插件均可），纯 JS，无 TS/JSX
const LOOPBACK_RE = /^(localhost|\[::1\]|127(\.\d{1,3}){3})$/;

function apply(ctx) {
  // 最小 fence 复刻：Host 必须 loopback；带 Origin 时必须同源；跨站标记拒绝
  function trusted(req) {
    const host = req.headers.host;
    if (!host) return false;
    const hostname = host.split(":")[0].replace(/^\[|\]$/g, "");
    if (!LOOPBACK_RE.test(hostname)) return false;
    if (req.headers["sec-fetch-site"] === "cross-site") return false;
    const origin = req.headers.origin;
    if (origin === undefined) return true;
    try { return new URL(origin).host === host; } catch { return false; }
  }

  // 读一个会话的 token 投影（live 用 registry 快照，cold 用持久化缓存快照）
  function tokenUsageOf(session, meta) {
    const projections = ctx.get("sessionProjections");
    if (session !== undefined && projections !== undefined) {
      return projections.snapshot(session).values.tokenUsage ?? null;   // {uncachedInputTokens, outputTokens, cacheReadTokens, cacheWriteTokens}
    }
    const cache = ctx.get("sessionProjectionCache");
    if (cache !== undefined && meta !== undefined) {
      return cache.cachedSnapshot(meta)?.values.tokenUsage ?? null;      // 零 I/O，identity 校验
    }
    return null;
  }

  ctx.effect(() => ctx.webServer.register({
    kind: "exact",
    path: "/api/desktop/stats",
    handler: async (req, res) => {
      if (!trusted(req)) { res.writeHead(403); res.end("forbidden"); return; }
      try {
        // 1) live 会话：sessions.list() + sessionProjections.snapshot()
        const rows = ctx.sessions.list().map((session) => {
          const tu = tokenUsageOf(session, undefined);
          const meta = ctx.get("sessionProjections")?.snapshot(session);
          return {
            sessionId: session.id,
            running: /* 可用 ctx.agents?.get(session.id)?.status === "running" 或省略 */ false,
            updatedAt: session.header.createdAt,        // 更精确的 updatedAt 用 sessionListMetadata.lastPromptAt 与 createdAt 取 max
            tokenUsage: tu,
            contextPressure: meta?.values.contextPressure ?? null,
            contextBreakdown: meta?.values.contextBreakdown ?? null,
            lastPromptAt: meta?.values.sessionListMetadata?.lastPromptAt ?? null
          };
        });
        // 2) cold 会话：sessionPersistence.list() + sessionProjectionCache.cachedSnapshot()
        const persistence = ctx.get("sessionPersistence");
        if (persistence !== undefined) {
          const liveIds = new Set(rows.map((r) => r.sessionId));
          for (const meta of (await persistence.list()).filter((m) => !liveIds.has(m.id))) {
            const tu = tokenUsageOf(undefined, meta);
            const proj = ctx.get("sessionProjectionCache")?.cachedSnapshot(meta);
            rows.push({
              sessionId: meta.id,
              running: false,
              updatedAt: Math.max(meta.createdAt, proj?.values.sessionListMetadata?.lastPromptAt ?? 0),
              tokenUsage: tu,
              contextPressure: proj?.values.contextPressure ?? null,
              contextBreakdown: proj?.values.contextBreakdown ?? null,
              lastPromptAt: proj?.values.sessionListMetadata?.lastPromptAt ?? null
            });
          }
        }
        // 3) 全会话汇总（菜单栏四个数字）
        const totals = { uncachedInputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 };
        for (const r of rows) if (r.tokenUsage) for (const k of Object.keys(totals)) totals[k] += r.tokenUsage[k] ?? 0;
        rows.sort((a, b) => b.updatedAt - a.updatedAt);
        const body = JSON.stringify({ sessions: rows, totals, generatedAt: Date.now() });
        res.writeHead(200, { "content-type": "application/json" });
        res.end(body);
      } catch (error) {
        res.writeHead(500, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: String(error) }));
      }
    }
  }), "desktop-stats-route");
}

module.exports = { name: "desktop-stats", inject: ["webServer", "sessions"], apply };
```

桌面端调用（与任务 1 相同的信封？不需要——这是自定义端点，直接纯 JSON）：

```bash
curl -sS http://127.0.0.1:3080/api/desktop/stats -H 'Host: 127.0.0.1:3080'
# → {"sessions":[{"sessionId":"...","running":false,"updatedAt":...,"tokenUsage":{"uncachedInputTokens":...,"outputTokens":...,"cacheReadTokens":...,"cacheWriteTokens":0},"contextPressure":{...},"contextBreakdown":{...},"lastPromptAt":...},...],"totals":{"uncachedInputTokens":...,"outputTokens":...,"cacheReadTokens":...,"cacheWriteTokens":0},"generatedAt":...}
```

关键服务/方法签名速查：

| 服务 | 注入名 | 方法 | 返回 |
|---|---|---|---|
| WebServer | `webServer` | `register({kind:"exact"\|"prefix", path, handler(req,res)})` | disposer |
| SessionStore | `sessions` | `list()` | `Session[]`（live，含 `.id`、`.header`、`.events`） |
| 投影注册表 | `sessionProjections` | `snapshot(session)` | `{asOfSeq, values}`（values.tokenUsage 即四桶累计） |
| 投影缓存 | `sessionProjectionCache` | `cachedSnapshot(meta)` | `{asOfSeq, values}|undefined`（冷会话，identity 校验） |
| 持久化 | `sessionPersistence` | `list(signal)`、`readFrom(id, seq, signal)` | `meta[]`、`{meta, events}` |
| Agent | `agents`（可选） | `get(sessionId)?.status` | `"running"\|"idle"` |

**备选方案（想复用 fence + 信封 + rpcId 相关）**：用 `ctx.connection.rpc.handle('/desktop', (endpoint, payload, signal) => value, {authority: "loopback"})`（`dsh-client-connection` 的 `HostConnectionService.rpc`，channel 为单段前缀、非 `/api`），URL 变成 `POST http://127.0.0.1:3080/desktop/stats`，body 用 full-form 信封，`method` 字段等于路径段（`"stats"`），fence 由框架内置（loopback 强制）。若坚持 `/api/desktop/stats` 路径，则用上述 exact 路由 + 自复刻 fence。

---

## 附：实测记录与备注

- 全部 curl 实测于本机 `http://127.0.0.1:3080`；`session.create` 创建的测试会话 `session-807d9c60-c191-4763-a113-0d3e130fc970`（cwd=/Users/iiiiiei/Desktop）已留存于 `~/.dsh/sessions/--Users-iiiiiei-Desktop--/`，仅消费了一次"你好"的少量 token。
- 实测 `cacheWriteTokens` 恒为 0（DeepSeek 官方 API 的 usage 无 cache 写入桶；`bucketsFrom` 用 `?? 0` 兜底）。
- 若 fence 403：检查 `Host` 头是否为 loopback 字面量；若带 `Origin`，确保与 Host 同源；`Sec-Fetch-Site` 不得为 `cross-site`。
- 若返回 `{"type":"server-response","result":{"ok":false,"error":{"code":"bad-request"}}}`：先核对 `method` 与路径一致、payload 满足该方法的 zod schema（如 session.create 的 workspaceId/cwd 互斥）。
