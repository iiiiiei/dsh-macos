# DSH Desktop — DeepSeek Harness 的 macOS 桌面应用

把 DeepSeek Harness 变成一台真正的桌面应用：**原生 macOS 外壳（SwiftUI）+ WKWebView 内嵌 Web GUI + 服务器生命周期管理 + 菜单栏常驻 + 原生通知**——而这一切都建立在 DSH 的插件生态之上，没有重写任何 UI。

```text
双击 .app  →  3 秒冷启动  →  DSH 服务器自动拉起  →  桌面窗口加载 Web GUI
```

## 功能特性

- **内嵌 DSH Web GUI**：WKWebView 加载 `http://127.0.0.1:<port>/`（默认 3080），沉浸式窗口（fullSizeContentView 内容顶到顶、红绿灯悬浮）+ 原生菜单 + 跟随系统深色模式
- **会话导出下载**：WKWebView 拦截 /api/session.export 由原生保存到 ~/Downloads（修复浏览器下载在 WKWebView 中不落地的问题）
- **服务器生命周期管理**
  - 启动时检测端口：已有实例 → attach（不干扰现有服务器）；无实例 → 自动冷启动
  - 健康轮询：启动阶段 0.5s 加密探测，运行后 5s 慢轮询；服务器挂掉自动提示
  - 退出策略：应用自己启动的服务器默认随应用退出（可配置保持运行）
- **菜单栏常驻**（🐋 官方鲸鱼模板图标，自动适配深浅色；macOS 原生菜单）：状态指示（绿/黄/红）、**token 用量统计**（竖向三行，官方口径）、浏览器打开、刷新、启动/停止服务器、测试通知、前往开放平台、退出
- **Token 用量统计**：口径与 DSH 官方 StatsLine 完全一致（`billedInput = uncached + cacheRead + cacheWrite`、缓存命中率 = cacheRead/billed）；**跟随 GUI 当前打开的对话窗口**（WebView 注入 fetch 钩子监听会话切换），无会话时退回最近活跃/今日聚合（直连 DSH RPC，无需插件激活）
- **设置**：端口、启动命令、自动启动服务器、退出时保持服务器、开机自启（SMAppService）；设置入口在应用菜单（Cmd+,），菜单栏不重复放
- **菜单栏常驻（DSH Launcher）**：独立轻量 Launcher 应用（GeminiAppLauncher 模式，LSUIElement 无 Dock 图标）：鲸鱼小图标常驻菜单栏，左键点击启动/唤起主应用，右键菜单可设"登录时自动启动"（以 SMAppService.mainApp.status 为唯一真相）；主应用 Dock"退出"= 干净退出，菜单栏图标由 Launcher 保证永远在
- **窗口菜单**：每次打开前自动补齐系统级控制（居中窗口/移到左右半屏/切换全屏）
- **汉化补丁**：`scripts/i18n-patch.py` 修复 DSH 官方 i18n 遗漏（Session log 按钮、Full access 权限选项、轨迹面板 51 条、斜杠命令描述 5 条），幂等可重跑，重启 DSH 后生效
- **桌面桥接插件**（dsh-desktop-bridge）：`/api/desktop/status` + `/api/desktop/notify`（+ `/api/desktop/stats`），桌面集成本身就是一个 DSH 插件
- **自测模式**：`--selftest` 端到端验证，CI 可用
- **冷启动优化**：命令解析结果缓存、launchd 环境零 PATH 依赖（详见 [架构](#架构)）

## 架构

### 为什么"原生外壳 + 内嵌 Web UI"，而不是原生重写？

| 方案 | 内存 | 插件生态 |
|---|---|---|
| 内嵌 Web UI（WKWebView） | 服务端 node 进程 + WebKit 渲染，多约 150–300MB（macOS 会自动回收后台 WebKit 内存） | **100% 保留**：DSH 的整个 UI 就是一组 Cordis 客户端插件（工具卡片、子代理面板、插件面板、目标/任务……），新插件自动获得桌面 UI |
| 原生重写聊天界面 | 省掉渲染进程 | 全部失效：每个插件的 UI 贡献都要重写一份，且 DSH 能力远多于聊天 |

### 分层

```text
┌─────────────────────────────────────────────────────────┐
│ UI 层（SwiftUI）                                         │
│   WindowGroup 主窗口（状态面板 ⇄ WebView）               │
│   MenuBarExtra 原生菜单栏 ⚡🛡（状态 + 统计 + 操作）       │
│   Settings 设置窗口（Cmd+,）                             │
├─────────────────────────────────────────────────────────┤
│ Web 层（WebKit）                                         │
│   WKWebView 内嵌 DSH Web GUI（原生 WebKit 渲染）         │
│   首次加载保护 / SPA 路由不打断 / 刷新 / 弹窗接管        │
├─────────────────────────────────────────────────────────┤
│ 进程层（ServerManager）                                  │
│   attach 检测 → 命令解析（缓存）→ spawn → 健康轮询 → 停止 │
│   /bin/zsh -c "exec <绝对命令> --port N"                │
├─────────────────────────────────────────────────────────┤
│ 数据层（直连 DSH RPC，无需插件）                          │
│   session.create/prompt/history  迷你输入发送             │
│   session.list  projections.tokenUsage  token 统计        │
│ 桥接层（dsh-desktop-bridge 插件，可选激活）               │
│   GET /api/desktop/status · POST /api/desktop/notify      │
└─────────────────────────────────────────────────────────┘
```

### 冷启动链路（实测数据）

```text
双击 / Launchpad（launchd，PATH 极简）
  ├─ attach 探测端口（连接被拒 → 立即失败）           ~0.1s
  ├─ 命令解析：缓存命中 0s / 首次 +0.4s               ~0–0.4s
  ├─ spawn：zsh -c "exec 绝对node 绝对bin.js --port"  ~0.2s
  ├─ dsh 服务器启动（node + Cordis 树加载）           1.0–1.6s
  ├─ 0.5s 加密健康轮询发现就绪                       ≤0.5s
  └─ WKWebView 加载 SPA                                ~1.5s
────────────────────────────────────────────────────────
  总计：首次 ~3.0s / 二次 ~3.1s（实测，见 [性能](#性能)）
```

### 关键设计决策

1. **launchd 零 PATH 依赖**：双击启动时 PATH 只有系统目录（无 Homebrew、无 npx 缓存）。命令解析链：`UserDefaults 缓存 → 绝对路径候选 → 登录 shell（注入 bin 目录）→ 绝对 node 直跑 npx 缓存里的 dsh 入口 → 绝对 npx`。spawn 时注入 Homebrew bin 目录，解决 `#!/usr/bin/env node` 找不到 node 的问题。
2. **解析结果缓存**：首次解析成功后写入 UserDefaults，后续启动零解析成本；缓存失效（文件被删）自动重新解析。
3. **attach 不覆盖自己启动的服务器**：`startedByUs` 标记决定退出时是否带走服务器；窗口重开导致的重复 attach 不会把应用自己拉起的服务器变成孤儿进程。
4. **避免 SwiftUI 重渲染循环**：`@Published` 每次赋值（即使值相同）都会触发视图更新；桥接轮询与页面状态只在值变化时赋值，否则 WebView 会被反复重载。
5. **Cordis `ctx.effect` 语义**：`ctx.effect(callback)` 会立即执行 callback 并把返回值当作 disposer——插件里注册路由必须包一层箭头函数返回 disposer。
6. **已知 macOS 怪癖**：给应用传两个连续的 `--flag` 参数会让 AppKit 的窗口创建卡住约 30 秒（与参数名无关）——自测结果路径因此走环境变量而非第二个命令行参数。

## 目录结构

```text
dsh-macos/
├── Package.swift                  # SPM 清单（IDE 友好；实际构建走 scripts/build.sh）
├── Resources/Info.plist           # 应用 bundle 配置
├── Sources/DSHDesktop/
│   ├── DSHDesktopApp.swift        # @main：WindowGroup + MenuBarExtra + Settings + AppDelegate
│   ├── AppState.swift             # 设置（UserDefaults）+ 页面/桥接状态（@Published）
│   ├── ServerManager.swift        # 服务器进程：attach/解析/启动/轮询/停止
│   ├── WebView.swift              # WKWebView 封装（导航/弹窗/权限/刷新/会话钩子）
│   ├── ContentView.swift          # 状态面板 ⇄ Web GUI 切换 + 引导流程
│   ├── MenuBarView.swift          # 原生菜单栏内容（状态/统计/操作）
│   ├── SettingsView.swift         # 设置窗口（含开机自启 SMAppService）
│   ├── BridgeClient.swift         # 与 dsh-desktop-bridge 插件通信
│   ├── SelfTest.swift             # --selftest 端到端验证
│   └── Log.swift                  # 无缓冲 stderr 日志（便于终端/自测观测）
├── scripts/
│   ├── build.sh                   # 编译 + 打包 .app + 图标 + ad-hoc 签名（含 CLT 修复）
│   └── make-icon.swift            # 程序化生成 AppIcon.icns
├── Sources/DSHLauncher/            # 菜单栏常驻 Launcher（LSUIElement + SMAppService）
├── bridge/dsh-desktop-bridge/     # 桌面桥接插件（DSH 生态内的普通 Cordis 宿主插件）
├── scripts/i18n-patch.py          # DSH 官方 i18n 遗漏汉化补丁（幂等）
└── README.md
```

## 构建

环境：macOS 13+（开发机实测 macOS 15.2 / arm64），Swift 6 工具链。**无需完整 Xcode**（Command Line Tools 即可）：

```bash
bash scripts/build.sh
# 产物：build/DSH Desktop.app
open "build/DSH Desktop.app"
```

### 工具链修复说明

本机 CLT 若处于半更新状态（编译器与 SDK 版本不匹配 + `usr/include/swift/` 下同时存在
`module.modulemap` 与 `bridging.modulemap`），任何 Swift 编译都会报
`redefinition of module 'SwiftBridging'` / `this SDK is not supported by the compiler`。

`build.sh` 会自动生成 Swift 层 `-vfsoverlay`，把多余的 `module.modulemap` 映射为空文件绕过
（`.build/toolchain-fix/overlay.yaml`）。根治办法是让 CLT 自洽（`softwareupdate` 更新或重装
Command Line Tools）；CLT 正常后 overlay 仍会生成但无副作用。

## 安装与使用

1. **安装**：把 `build/DSH Desktop.app` 复制到 `/Applications/`（启动台才能识别）
2. **启动**：双击或 Launchpad 打开。首次会看到服务器状态面板（"正在冷启动 DSH 服务器（首次约需数秒）…"），就绪后自动切换为 Web GUI
3. **菜单栏（DSH Launcher）**：常驻鲸鱼小图标，左键点击启动主应用；主应用内顶部"服务器"菜单含全部操作（启停/刷新/浏览器/开放平台/测试通知）；关闭窗口不退出应用（Dock 常驻），Cmd+Q 退出

### 设置项

| 设置 | 默认 | 说明 |
|---|---|---|
| 端口 | 3080 | DSH 服务器监听端口（自动 clamp 到 1–65535） |
| 启动命令 | `dsh --profile web` | 会被解析为绝对命令并自动追加 `--port` |
| 自动启动服务器 | 开 | 启动应用时若端口无实例则自动拉起 |
| 退出时保持服务器 | 关 | 退出应用时是否带走应用自己启动的服务器 |
| 开机自动启动 | 关 | SMAppService；要求应用在 /Applications 且签名有效 |

## 自测

```bash
DSH_SELFTEST_OUTPUT=/tmp/selftest.json \
  "build/DSH Desktop.app/Contents/MacOS/DSHDesktop" --selftest
# 结果写入 /tmp/selftest.json（passed=true 即通过）；退出码 0/1
```

覆盖：应用启动 → attach/冷启动 → 服务器就绪 → 页面加载完成，全链路验证。

> 注意：结果路径走环境变量 `DSH_SELFTEST_OUTPUT`，不要用第二个 `--flag <path>` 参数
> （两个连续 `--flag` 会卡窗口约 30 秒，见 [架构 - 设计决策 6](#关键设计决策)）。

## 桥接插件（dsh-desktop-bridge）

一个普通的 Cordis 宿主插件，注册两个 exact 路由（优先于 `/api` prefix 路由，不影响浏览器 RPC）：

| 路由 | 说明 |
|---|---|
| `GET /api/desktop/status` | `{ok, pid, uptimeMs, version, profile}` |
| `POST /api/desktop/notify` | `{title, message}` → osascript 触发 macOS 原生通知 |

**安装**（写入 profile，重启 DSH 服务器后生效）：

```bash
# 1. 拷贝插件到 profile 的 node_modules（用拷贝而非软链，避免移动项目后破坏服务器启动）
cp -R bridge/dsh-desktop-bridge ~/.dsh/profiles/node_modules/dsh-desktop-bridge

# 2. 在 ~/.dsh/profiles/web/cordis.patch.yml 中加入：
#    - insert:
#        - id: desktop-bridge
#          name: 'dsh-desktop-bridge'
```

**卸载**：删除 patch 中的行 + 删除 `~/.dsh/profiles/node_modules/dsh-desktop-bridge/`。

## 性能

冷启动耗时实测（模拟"无终端 + 无 dsh 进程 + launchd 环境"）：

| 场景 | 耗时 | 说明 |
|---|---|---|
| 首次冷启动（无解析缓存） | **3.0s** | 含命令解析 +0.4s |
| 二次冷启动（有缓存） | **3.1s** | 日常场景 |
| spawn → 服务器就绪 | 1.0–1.6s | node + Cordis 树加载，物理下限 |

## 常见问题

| 问题 | 处理 |
|---|---|
| 启动台看不到应用 | 应用需在 `/Applications/`；复制后如未出现，`killall Dock` 刷新 |
| 开机自启失败 | 应用需在 /Applications 且签名有效；ad-hoc 签名可能被 SMAppService 拒绝（设置页有提示）。正式分发建议 Developer ID 签名 |
| 点"启动服务器"报"找不到命令" | 检查设置里的启动命令；应用会兜底 npx 缓存与绝对 npx |
| 端口被占用 | 应用会 attach 到已存在的实例（视为外部服务器，退出时不带走） |
| 页面加载失败 | 菜单栏 ⚡ → 刷新页面 |
| 分发给他人报"已损坏" | ad-hoc 签名仅限本机；分发需 Developer ID 签名 + 公证 |

## 路线图

- [ ] Developer ID 签名与公证，正式分发 + 开机自启
- [ ] 桥接插件扩展：服务器 → 桌面事件推送（任务完成 / 需要审批时原生通知）
- [ ] 原生标题栏 / 工具栏融合（traffic lights 与 GUI 顶栏整合）
- [ ] 打包 node + dsh 运行时，脱离系统 dsh 独立运行（零依赖分发）

## 开发

- 日志：所有关键路径走 `Log.info`（stderr，无缓冲），终端直接运行可观测
- 自测：改完代码跑 `scripts/build.sh` + `--selftest` 即可回归
- 桥接插件改动：改 `bridge/dsh-desktop-bridge/lib/index.js` 后重新拷贝到 profile 的 node_modules 并重启服务器
