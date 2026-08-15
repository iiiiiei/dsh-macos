# DSH Desktop — DeepSeek Harness 的 macOS 桌面应用

原生 macOS 应用（SwiftUI + WKWebView），把 DeepSeek Harness 变成一台真正的桌面应用：
内嵌 Web GUI、自动管理 `dsh` 服务器进程、菜单栏常驻、原生通知——而这一切都建立在 DSH 的
插件生态之上，没有重写任何 UI。

## 为什么是"原生外壳 + 内嵌 Web UI"？

| 方案 | 内存 | 插件生态 |
|---|---|---|
| 内嵌 Web UI（WKWebView） | 服务端 node 进程 + WebKit 渲染，合计约多 150–300MB（macOS 会自动回收后台 WebKit 内存） | **100% 保留**：DSH 的整个 UI 就是一组 Cordis 客户端插件（工具卡片、子代理面板、插件面板、目标/任务……），新插件自动获得桌面 UI |
| 原生重写聊天界面 | 省掉渲染进程 | 全部失效：每个插件的 UI 贡献都要重写一份，且 DSH 能力远多于聊天 |

结论：内嵌 Web UI 是唯一沿袭 DSH 插件精神的路径。桌面集成本身也做成了一个 DSH 插件
（`dsh-desktop-bridge`），与生态里其它插件平起平坐。

## 功能

- **内嵌 DSH Web GUI**：WKWebView 加载 `http://127.0.0.1:<port>/`（默认 3080），
  原生窗口 + 原生菜单 + 深色模式跟随系统
- **服务器生命周期管理**：
  - 启动时检测端口上是否已有 DSH 实例（attach 模式，不干扰现有服务器）
  - 没有则按设置自动启动 `dsh --profile web --port <port>`
  - 健康轮询，服务器挂掉自动提示；退出应用时可选择是否带走服务器
- **菜单栏常驻**：状态点（绿=运行 / 黄=启动中 / 红=错误）、打开主窗口、浏览器打开、
  刷新页面、启动/停止服务器、发送测试通知、设置、退出
- **设置**：端口、启动命令、自动启动服务器、退出时保持服务器、开机自启（SMAppService）
- **桌面桥接插件**（可选）：`/api/desktop/status` + `/api/desktop/notify`，
  菜单栏可一键发送原生通知，设置里显示服务器 pid/版本/运行时长
- **自测模式**：`--selftest` 端到端验证（服务器就绪 + 页面加载），CI 可用

## 构建（无完整 Xcode 也可）

本机环境：macOS 15.2 (arm64)，仅 Command Line Tools（无 Xcode）。构建脚本用
`swiftc` 直接编译 + 手动组装 `.app` + ad-hoc 签名：

```bash
bash scripts/build.sh
# 产物：build/DSH Desktop.app
open "build/DSH Desktop.app"
```

### 工具链修复说明（重要）

本机 CLT 处于半更新状态：编译器 `swiftlang-6.0.3.1.10` 与 SDK 的 `1.5` 混装，且
`/Library/Developer/CommandLineTools/usr/include/swift/` 下同时存在
`module.modulemap` 与 `bridging.modulemap`，导致编译任何 Swift 程序都报
`redefinition of module 'SwiftBridging'` 与 `this SDK is not supported by the compiler`。

`build.sh` 会自动生成一个 Swift 层 `-vfsoverlay`，把多余的 `module.modulemap` 映射为
空文件绕过该问题（`.build/toolchain-fix/overlay.yaml`）。**根治办法**是让 CLT 自洽
（`softwareupdate` 更新或重装 Command Line Tools），之后 `build.sh` 的 overlay 仍会生成
但已无副作用；也可以改回 `swift build`（`Package.swift` 已就绪，需把 overlay 参数并入）。

## 使用

1. 启动应用：窗口出现后自动检测/启动 DSH 服务器并加载 GUI
2. 首次会看到"DeepSeek Harness 服务器"状态面板 —— 点"启动服务器"，或检查设置里的
   启动命令（默认 `dsh --profile web`，应用会解析成绝对路径并追加 `--port`）
3. 菜单栏 ⚡ 图标常驻：快捷操作都在这里
4. 关闭窗口不会退出应用（菜单栏常驻）；Cmd+Q 退出

## 自测

```bash
DSH_SELFTEST_OUTPUT=/tmp/selftest.json \
  "build/DSH Desktop.app/Contents/MacOS/DSHDesktop" --selftest
# 结果写入 /tmp/selftest.json，passed=true 即通过；进程退出码 0/1
```

> 注意：结果路径通过环境变量 `DSH_SELFTEST_OUTPUT` 传递，**不要**用第二个
> `--selftest-output <path>` 命令行参数——两个连续的 `--flag` 会让 AppKit 的窗口创建
> 卡住约 30 秒（与参数名无关的 macOS 环境行为，已在 `SelfTest.swift` 注释中说明）。

## 桌面桥接插件（dsh-desktop-bridge）

一个普通的 Cordis 宿主插件，注册两个路由：

| 路由 | 说明 |
|---|---|
| `GET /api/desktop/status` | `{ok, pid, uptimeMs, version, profile}` |
| `POST /api/desktop/notify` | `{title, message}` → osascript 触发 macOS 原生通知 |

**安装**（已在本机完成，下次重启 DSH 服务器生效）：

1. 把插件拷入 profile 的 node_modules：
   ```bash
   cp -R bridge/dsh-desktop-bridge ~/.dsh/profiles/node_modules/dsh-desktop-bridge
   ```
   （用拷贝而非软链，避免移动项目目录后破坏服务器启动）
2. 在 `~/.dsh/profiles/web/cordis.patch.yml` 中加入：
   ```yaml
   - insert:
       - id: desktop-bridge
         name: 'dsh-desktop-bridge'
   ```
3. 重启 DSH 服务器，应用菜单栏会显示"桥接插件已连接"，设置页可见 pid/版本/运行时长

**卸载**：删掉 patch 中的行 + 删掉 `~/.dsh/profiles/node_modules/dsh-desktop-bridge/`。

## 目录结构

```
dsh-macos/
├── Package.swift                  # SPM 清单（IDE 友好；构建走 build.sh）
├── Resources/Info.plist           # 应用 bundle 配置
├── Sources/DSHDesktop/
│   ├── DSHDesktopApp.swift        # @main：WindowGroup + MenuBarExtra + Settings
│   ├── AppState.swift             # 设置 + 页面/桥接状态（@Published）
│   ├── ServerManager.swift        # dsh 进程：attach/启动/轮询/停止
│   ├── WebView.swift              # WKWebView 封装（导航/弹窗/权限）
│   ├── ContentView.swift          # 状态面板 ↔ Web GUI 切换
│   ├── MenuBarView.swift          # 菜单栏内容
│   ├── SettingsView.swift         # 设置窗口（含开机自启）
│   ├── BridgeClient.swift         # 与 dsh-desktop-bridge 通信
│   ├── SelfTest.swift             # --selftest 端到端验证
│   └── Log.swift                  # 无缓冲 stderr 日志
├── scripts/build.sh               # 编译 + 打包 + 签名（含 CLT 修复）
├── scripts/make-icon.swift        # 生成 AppIcon.icns
└── bridge/dsh-desktop-bridge/     # 桌面桥接插件（DSH 生态内）
```

## 已知问题与注意事项

- **开机自启**（SMAppService）要求应用在 `/Applications` 且签名有效；ad-hoc 签名可能
  被拒绝，设置页会给出错误提示。正式分发建议用 Developer ID 签名。
- 应用 ad-hoc 签名仅限本机使用；分发给他人需重新签名。
- 桥接插件的 `/api/desktop/*` 为 exact 路由，优先于 `/api` prefix 路由，
  不会影响浏览器 RPC。
- 若 CLT 更新到自洽版本，`build.sh` 里的 overlay 步骤可删除（保留亦无害）。
- 本机正在运行的 DSH 服务器不会被本次安装影响；桥接插件在下一次服务器重启后激活。

## 路线图

- [ ] Developer ID 签名与公证，支持正式分发 + 开机自启
- [ ] 桥接插件扩展：服务器 → 桌面事件推送（任务完成/需要审批时原生通知）
- [ ] 原生标题栏/工具栏融合（traffic lights 与 GUI 顶栏整合）
- [ ] 打包 node + dsh 运行时，脱离系统 dsh 独立运行
