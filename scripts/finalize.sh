#!/bin/bash
# 最终清理：重写 README（基于最新代码真相）→ 删 .research + i18n 死脚本 → 修 verify 锚点 → 提交推送 → 同步 Desktop
# 在你的终端运行（Desktop 受 TCC 保护）
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> [1/6] 重写 README.md"
cat > README.md << 'README_EOF'
# DSH Desktop —— DeepSeek Harness 的 macOS 桌面应用

把 DeepSeek Harness 变成一台真正的桌面应用：**原生 macOS 外壳（SwiftUI + AppKit）+ WKWebView 内嵌官方 Web GUI + 服务器生命周期管理 + 原生通知**，全部构建在 DSH 插件生态之上，不重写任何 UI。

```text
双击 .app  →  3 秒冷启动  →  DSH 服务器自动拉起  →  桌面窗口加载官方 Web GUI
```

## 设计理念

极简轻量外壳：不重写 UI、不搬运逻辑，只做三件事——把 DSH 服务器拉起来、把官方 Web UI 装进原生窗口、用原生能力补齐 Web 做不到的事。运行内存占用显著低于 Electron 类方案。

## 功能特性

- **内嵌官方 Web GUI**：WKWebView 加载 `http://127.0.0.1:<port>/`（默认 3080），沉浸式窗口（fullSizeContentView 内容顶到顶、红绿灯悬浮）+ 原生菜单 + 跟随系统深色模式
- **会话导出下载**：WKWebView 拦截 `/api/session.export` 由原生保存到 `~/Downloads`
- **服务器生命周期管理**
  - 启动时检测端口：已有实例 → attach（不干扰现有服务器）；无实例 → 自动冷启动
  - **后端唯一性**：spawn 前再探一次端口，已有健康实例则转 attach，绝不拉起第二个后端
  - 健康轮询：启动阶段 0.5s 加密探测，运行后 5s 慢轮询；手动停止/进程退出后轮询立即停止（不空转）
  - 退出策略：应用自己启动的服务器默认随应用退出（可配置保持运行）
- **原生通知**：`UserNotifications` 框架，通知归属 "DSH Desktop"，系统设置 → 通知 里可见可管（不再依赖 osascript 桥接）
- **原生菜单**（顶部菜单栏"服务器"）：启动/停止服务器、刷新页面、显示主窗口、在浏览器中打开、前往开放平台、发送测试通知
- **设置**（Cmd+,）：端口、启动命令、自动启动服务器、退出时保持服务器、开机自启（SMAppService）
- **Desktop 布局对齐**：以红绿灯作为不可变参考系——红绿灯组整体平移到中心锚点 (23,23)、不改按钮相对位置；折叠侧栏宽 86px（灯组中心 x=43 在侧栏水平中心）；官方 56px 轨居中；透明拖拽带行高 46px（红绿灯垂直居中）；展开/折叠态 logo 行下边界对齐右侧会话顶栏
- **自动验证**：`bash scripts/verify-desktop-appearance.sh`（窗口 flags/可逆、无魔法数、WebView 透明、图标、无轮询）+ `bash scripts/verify-desktop-layout.sh`（布局对齐运行时断言）
- **冷启动优化**：命令解析结果缓存、launchd 环境零 PATH 依赖

## 架构

### 为什么"原生外壳 + 内嵌 Web UI"，而不是原生重写？

| 方案 | 内存 | 插件生态 |
|---|---|---|
| 内嵌 Web UI（WKWebView） | 服务端 node 进程 + WebKit 渲染（macOS 会自动回收后台 WebKit 内存） | **100% 保留**：DSH 的整个 UI 就是一组 Cordis 客户端插件，新插件自动获得桌面 UI |
| 原生重写聊天界面 | 省掉渲染进程 | 全部失效：每个插件的 UI 贡献都要重写一份 |

### 分层

```text
┌─────────────────────────────────────────────────────────┐
│ UI 层（SwiftUI / AppKit）                                │
│   WindowGroup 主窗口（状态面板 ⇄ WebView）               │
│   CommandMenu 原生菜单（"服务器"）                       │
│   Settings 设置窗口（Cmd+,）                             │
├─────────────────────────────────────────────────────────┤
│ Web 层（WebKit）                                         │
│   WKWebView 内嵌官方 Web GUI（原生 WebKit 渲染）         │
│   首次加载保护 / SPA 路由不打断 / 刷新 / 弹窗接管        │
│   desktop-layout.js overlay：只改几何不碰官方源码树      │
├─────────────────────────────────────────────────────────┤
│ 进程层（ServerManager）                                  │
│   attach 检测 → 唯一性检查 → 命令解析（缓存）→ spawn     │
│   → 健康轮询 → 停止（停止即停轮询，不空转）             │
├─────────────────────────────────────────────────────────┤
│ 桥接层（dsh-desktop-bridge 插件，可选激活）              │
│   GET /api/desktop/status（服务器状态）                  │
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

1. **launchd 零 PATH 依赖**：双击启动时 PATH 只有系统目录。命令解析链：`UserDefaults 缓存 → 绝对路径候选 → 登录 shell（注入 bin 目录）→ 绝对 node 直跑 npx 缓存里的 dsh 入口 → 绝对 npx`。
2. **解析结果缓存**：首次解析成功写入 UserDefaults，后续零解析成本。
3. **attach 不覆盖自己启动的服务器**：`startedByUs` 标记决定退出时是否带走服务器。
4. **后端唯一性**：spawn 前再探一次端口，已有健康实例转 attach，杜绝双后端。
5. **避免 SwiftUI 重渲染循环**：`@Published` 只在值变化时赋值，否则 WebView 会被反复重载。
6. **已知 macOS 怪癖**：给应用传两个连续的 `--flag` 参数会让 AppKit 窗口创建卡住约 30 秒。
7. **Cordis `ctx.effect` 语义**：`ctx.effect(callback)` 立即执行并把返回值当 disposer——注册路由必须包箭头函数返回。

## 目录结构

```text
dsh-macos/
├── Package.swift                  # SPM 清单（IDE 友好；实际构建走 scripts/build.sh）
├── Resources/Info.plist           # 应用 bundle 配置
├── Sources/DSHDesktop/
│   ├── DSHDesktopApp.swift        # @main：WindowGroup + CommandMenu + Settings + AppDelegate
│   ├── AppState.swift             # 设置（UserDefaults）+ 页面/桥接状态（@Published）
│   ├── ServerManager.swift        # 服务器进程：attach/唯一性/解析/启动/轮询/停止
│   ├── WebView.swift              # WKWebView 封装（导航/弹窗/权限/刷新/overlay 注入）
│   ├── ContentView.swift          # 状态面板 ⇄ Web GUI 切换 + 引导流程
│   ├── SettingsView.swift         # 设置窗口（含开机自启 SMAppService）
│   ├── BridgeClient.swift         # 与 dsh-desktop-bridge 插件通信（status）
│   └── DesktopLayout.swift        # 布局常量（红绿灯锚点/侧栏宽度/拖拽带）
├── Resources/overlays/
│   └── desktop-layout.js          # 布局 overlay（只改几何，不碰官方源码树）
├── bridge/dsh-desktop-bridge/     # 桌面桥接插件（DSH 生态内的普通 Cordis 宿主插件）
├── scripts/
│   ├── build.sh                   # 编译 + 打包 .app + 图标 + ad-hoc 签名
│   ├── make-icon.swift            # 程序化生成 AppIcon.icns（白底黑鲸）
│   ├── verify-desktop-appearance.sh # 桌面外观自动验证
│   └── verify-desktop-layout.sh   # Desktop 布局对齐自动验证
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

本机 CLT 若处于半更新状态（编译器与 SDK 版本不匹配 + `usr/include/swift/` 下同时存在 `module.modulemap` 与 `bridging.modulemap`），任何 Swift 编译都会报 `redefinition of module 'SwiftBridging'`。`build.sh` 会自动生成 Swift 层 `-vfsoverlay` 绕过（`.build/toolchain-fix/overlay.yaml`）。

## 安装与使用

1. **安装**：把 `build/DSH Desktop.app` 复制到 `/Applications/`
2. **启动**：双击或 Launchpad 打开。首次会看到服务器状态面板，就绪后自动切换为 Web GUI
3. **菜单**：顶部"服务器"菜单含全部操作（启停/刷新/浏览器/开放平台/测试通知）；关闭窗口不退出应用（Dock 常驻），Cmd+Q 退出

### 设置项

| 设置 | 默认 | 说明 |
|---|---|---|
| 端口 | 3080 | DSH 服务器监听端口（自动 clamp 到 1–65535） |
| 启动命令 | `dsh --profile web` | 会被解析为绝对命令并自动追加 `--port` |
| 自动启动服务器 | 开 | 启动应用时若端口无实例则自动拉起 |
| 退出时保持服务器 | 关 | 退出应用时是否带走应用自己启动的服务器 |
| 开机自动启动 | 关 | SMAppService；要求应用在 /Applications 且签名有效 |

## 桥接插件（dsh-desktop-bridge）

一个普通的 Cordis 宿主插件，注册 exact 路由（优先于 `/api` prefix 路由，不影响浏览器 RPC）：

| 路由 | 说明 |
|---|---|
| `GET /api/desktop/status` | `{ok, pid, uptimeMs, version, profile}` |

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
| 开机自启失败 | 应用需在 /Applications 且签名有效；ad-hoc 签名可能被 SMAppService 拒绝。正式分发建议 Developer ID 签名 |
| 点"启动服务器"报"找不到命令" | 检查设置里的启动命令；应用会兜底 npx 缓存与绝对 npx |
| 端口被占用 | 应用会 attach 到已存在的实例（视为外部服务器，退出时不带走） |
| 页面加载失败 | 菜单 → 刷新页面 |
| 分发给他人报"已损坏" | ad-hoc 签名仅限本机；分发需 Developer ID 签名 + 公证 |

## 路线图

- [ ] Developer ID 签名与公证，正式分发 + 开机自启
- [ ] 打包 node + dsh 运行时，脱离系统 dsh 独立运行（零依赖分发）
- [ ] 跟随官方 dsh 版本升级（当前 rc.7）

## 开发

- 桥接插件改动：改 `bridge/dsh-desktop-bridge/lib/index.js` 后重新拷贝到 profile 的 node_modules 并重启服务器
- dsh 版本升级：更新 `@deepseek-ai/dsh` 后重启服务器即可，外壳代码无需适配（rc.7 验证过）
README_EOF
echo "OK   README.md 已按最新代码重写"

echo "==> [2/6] 删除 .research + i18n 死脚本"
rm -rf .research
rm -f scripts/i18n-patch.py scripts/i18n-patch.sh scripts/i18n-scan.py
echo "OK   已删除 .research/ 与 3 个 i18n 脚本"

echo "==> [3/6] 修正 verify-desktop-layout.sh 红绿灯锚点 (23,24)→(23,23)"
python3 << 'PYEOF'
import pathlib
p = pathlib.Path('scripts/verify-desktop-layout.sh')
t = p.read_text()
t = t.replace("traffic aligned:.*targetCenter=(23,24)", "traffic aligned:.*targetCenter=(23,23)")
t = t.replace("已对齐到中心锚点 (23,24)", "已对齐到中心锚点 (23,23)")
p.write_text(t)
print("OK   锚点已修正")
PYEOF

echo "==> [4/6] git 删除 + 提交 + 推送"
git add -A
git status --short | head -15
git commit -m "$(cat <<'MSG'
docs: 重写 README 对齐最新代码（86px/锚点23,23/原生通知/无token统计）；删除残留 .research 协议笔记与 i18n 死脚本；修正 verify 红绿灯锚点

- README：按最新真相重写（折叠侧栏 86px、红绿灯锚点 (23,23)、拖拽带 46px、原生通知、无 token 统计、桥接仅 status）
- 删除 .research/dsh-protocol.md（token 统计遗留协议笔记，无引用）
- 删除 scripts/i18n-patch.*、i18n-scan.py（汉化已删，无引用）
- verify-desktop-layout.sh：红绿灯锚点校验 (23,24)→(23,23)
MSG
)" || echo "无待提交改动"
git push origin HEAD || echo "!! 推送失败，请手动: git push"

echo "==> [5/6] 同步到 ~/Desktop/dsh-macos"
SRC="$(pwd)"
DST="$HOME/Desktop/dsh-macos"
if [ -d "$DST" ]; then
  rsync -a --delete \
    --exclude='.build/' --exclude='build/' --exclude='.DS_Store' \
    --exclude='*.removed' \
    "$SRC/" "$DST/"
  echo "OK   $DST 已同步（含新 README、无 .research、无 i18n）"
else
  echo "!! $DST 不存在，跳过同步"
fi

echo "==> [6/6] 完成"
git status -sb | head -1
