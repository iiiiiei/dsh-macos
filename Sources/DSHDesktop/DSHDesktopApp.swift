import SwiftUI
import AppKit
import WebKit

@main
struct DSHDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var server = ServerManager.shared

    /// 官方鲸鱼模板图标（黑白自动适配，等价于网页版 favicon 的深浅色切换）。
    /// 菜单栏常驻由 DSH Launcher 提供，本图标仅作为资源保留。
    static let whaleIcon: NSImage = {
        let path = Bundle.main.path(forResource: "whale-icon", ofType: "png")
            ?? Bundle.main.path(forResource: "whale", ofType: "svg")
        let image = path.flatMap { NSImage(contentsOfFile: $0) }
            ?? NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "DSH Desktop")!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        WindowGroup("DSH Desktop", id: "main") {
            ContentView(appState: appState, server: server)
        }
        .defaultSize(width: 1280, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            // 去掉默认的“新建窗口”
            CommandGroup(replacing: .newItem) {}

            CommandMenu("服务器") {
                Button(server.status == .running ? "停止服务器" : "启动服务器") {
                    if server.status == .running {
                        server.stop()
                    } else {
                        server.start()
                    }
                }
                .disabled(server.status == .starting)

                Divider()

                Button("刷新页面") {
                    NotificationCenter.default.post(name: .dshReloadRequested, object: nil)
                }
                Button("显示主窗口") {
                    if let window = NSApp.windows.first(where: { $0.title.hasPrefix("DSH Desktop") }) {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                Button("在浏览器中打开") {
                    NSWorkspace.shared.open(AppState.shared.url)
                }
                Button("前往开放平台") {
                    NSWorkspace.shared.open(URL(string: "https://platform.deepseek.com/")!)
                }

                Divider()

                if appState.bridgeConnected {
                    Button("发送测试通知（桥接插件）") {
                        Task { @MainActor in
                            let ok = await BridgeClient.shared.notify(
                                title: "DSH Desktop",
                                message: "来自 dsh-desktop-bridge 插件的原生通知 ✅",
                                appState: appState
                            )
                            notifyResult(ok)
                        }
                    }
                } else {
                    Text("桥接插件未激活（重启 DSH 后可用）")
                }
            }
        }

        Settings {
            SettingsView(appState: appState, server: server)
        }
    }

    /// 菜单里无法就地反馈，用系统通知展示结果
    private func notifyResult(_ ok: Bool) {
        let script = ok
            ? "display notification \"已触发原生通知\" with title \"DSH Desktop\""
            : "display notification \"桥接插件未激活，请重启 DSH 服务器\" with title \"DSH Desktop\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var fullSizeApplied = false
    private var dragStrip: DragStripView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("applicationDidFinishLaunching")
        // 从终端直接运行二进制时也需要常规 Dock 应用行为
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 沉浸式窗口：等主窗口出现后设置透明标题栏 + 内容延伸（红绿灯悬浮、内容顶到顶）。
        // 受「沉浸式标题栏」开关控制（默认开，关闭后回到系统标准标题栏）。
        applyWindowEnhancements()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil
        )
        // 设置变化（UserDefaults）时幂等重放窗口增强，支持运行时开关
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyWindowEnhancements()
        }
        // 窗口尺寸变化时跟随拖拽带（Low Memory：事件驱动，无轮询）
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow,
                  window.title.hasPrefix("DSH Desktop") else { return }
            self?.layoutDragStrip(window)
        }
        // 网页加载完成后把拖拽带重新置顶（SwiftUI 晚插入的 WKWebView 会盖住先加入的拖拽带）
        NotificationCenter.default.addObserver(
            forName: .dshWebViewLoaded, object: nil, queue: .main
        ) { [weak self] notification in
            guard let webView = notification.object as? WKWebView,
                  let window = webView.window else { return }
            self?.installDragStrip(in: window)
        }

        // 窗口菜单补充：每次打开前确保系统级控制项在位
        ensureWindowMenu()

        if CommandLine.arguments.contains("--selftest") {
            Task { @MainActor in
                await SelfTest.run(appState: AppState.shared, server: ServerManager.shared)
            }
        }
    }

    // MARK: - 沉浸式窗口（顶到顶）

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        applyWindowEnhancements()
    }

    /// 沉浸式标题栏（幂等，可逆）：
    /// 开 = 红绿灯悬浮、内容顶到顶；关 = 系统标准标题栏（恢复官方观感）
    private func applyWindowEnhancements() {
        let immersive = AppState.shared.immersiveTitlebar
        for window in NSApp.windows where window.title.hasPrefix("DSH Desktop") {
            if immersive {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarSeparatorStyle = .none
            } else {
                window.titlebarAppearsTransparent = false
                window.titleVisibility = .visible
                window.styleMask.remove(.fullSizeContentView)
                window.titlebarSeparatorStyle = .automatic
            }
            fullSizeApplied = true
            // 拖拽带：红绿灯水平行整行可拖（原生 performDrag）
            installDragStrip(in: window)
            // 红绿灯保持系统默认绝对位置（折叠侧栏宽度按此锚点适配居中）
        }
        if fullSizeApplied {
            Log.info("window: 沉浸式标题栏 = \(immersive ? "开（顶到顶）" : "关（标准标题栏）")")
        }
        // 运行时几何断言：contentView 是否覆盖到窗口顶部（用于自动验证）
        if let window = NSApp.windows.first(where: { $0.title.hasPrefix("DSH Desktop") }) {
            let wf = window.frame
            let cf = window.contentView?.frame ?? .zero
            Log.info("window: frame=\(Int(wf.height)) contentView=\(Int(cf.height)) edgeToEdge=\(Int(cf.height) >= Int(wf.height) - 1)")
        }
    }

    // MARK: - 窗口菜单补充（SwiftUI 只保留最小化/缩放/前置全部窗口/窗口列表）

    private func ensureWindowMenu() {
        guard let menu = NSApp.windowsMenu else { return }
        menu.delegate = self
        if menu.items.contains(where: { $0.tag == 9001 }) { return }
        menu.addItem(.separator())
        let center = NSMenuItem(title: "居中窗口", action: #selector(centerWindow(_:)), keyEquivalent: "")
        let left = NSMenuItem(title: "移到左侧半屏", action: #selector(moveWindowLeft(_:)), keyEquivalent: "")
        let right = NSMenuItem(title: "移到右侧半屏", action: #selector(moveWindowRight(_:)), keyEquivalent: "")
        let full = NSMenuItem(title: "切换全屏", action: #selector(toggleFullScreen(_:)), keyEquivalent: "f")
        for item in [center, left, right, full] { item.tag = 9001 }
        [center, left, right, full].forEach { menu.addItem($0) }
        Log.info("window menu: 已补充窗口管理项")
    }

    /// NSMenuDelegate：窗口菜单每次打开前确保补充项在位
    func menuWillOpen(_ menu: NSMenu) {
        ensureWindowMenu()
    }

    // MARK: - 拖拽带（方案1：红绿灯右侧约 32 CSS px 透明拖拽）

    private func installDragStrip(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        if let strip = dragStrip, strip.window === window {
            // 拖拽带必须始终是 contentView 的最后一个子视图（最上层）：
            // SwiftUI 在服务器就绪后插入的 WKWebView 会排到拖拽带之上，
            // 导致拖拽带永远收不到鼠标事件（不可拖拽的根因）。
            if contentView.subviews.last !== strip {
                strip.removeFromSuperview()
                contentView.addSubview(strip)
                Log.info("drag strip: 重新置顶（WKWebView 曾盖住拖拽带）")
            }
            layoutDragStrip(window)
            return
        }
        let strip = DragStripView(frame: .zero)
        contentView.addSubview(strip)
        dragStrip = strip
        layoutDragStrip(window)
    }

    /// 拖拽带：红绿灯水平行整行（全宽），行高由红绿灯组件位置反推——
    /// 行高 = 按钮上边距 × 2 + 按钮高（按钮在行内垂直居中，轴线与行中心重合）。
    /// 行高单一来源 = contentLayoutRect 差值（与注入的 --dsh-traffic-inset 一致）。
    private func layoutDragStrip(_ window: NSWindow) {
        guard let strip = dragStrip, let contentView = window.contentView else { return }
        guard let close = window.standardWindowButton(.closeButton) else { return }
        // 红绿灯组件垂直范围（flipped 坐标：minY 即距顶）
        let rowHeight = max(DesktopLayout.trafficLightRowHeight,
                            window.frame.height - window.contentLayoutRect.height)
        let axisFromTop = close.frame.midY
        // 轴线在行内垂直居中；行夹取在窗口可视范围内
        let stripTopFromTop = max(0, axisFromTop - rowHeight / 2)
        // 坐标系：NSHostingView 是 flipped（原点左上），拖拽带 frame.y 直接取
        // 「距顶」；非 flipped 视图才用窗口高换算。此前按非 flipped 计算，
        // 拖拽带被放到了窗口底部（实测 cv.isFlipped=true，y=847 = 底部）——
        // 这是顶部不可拖拽的根因。
        let y = contentView.isFlipped
            ? stripTopFromTop
            : window.frame.height - stripTopFromTop - rowHeight
        strip.frame = NSRect(
            x: 0,
            y: y,
            width: contentView.bounds.width,
            height: rowHeight
        )
        Log.info("drag strip: x=\(Int(strip.frame.minX)) w=\(Int(strip.frame.width)) h=\(Int(strip.frame.height)) axisFromTop=\(Int(axisFromTop)) rowHeight=\(Int(rowHeight))")
    }

    private func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.title.hasPrefix("DSH Desktop") }
            ?? NSApp.keyWindow
    }

    @objc private func centerWindow(_ sender: Any?) {
        mainWindow()?.center()
    }

    @objc private func moveWindowLeft(_ sender: Any?) {
        moveWindow(toHalf: .minX)
    }

    @objc private func moveWindowRight(_ sender: Any?) {
        moveWindow(toHalf: .maxX)
    }

    private func moveWindow(toHalf edge: NSRectEdge) {
        guard let window = mainWindow(), let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let half = NSRect(x: edge == .minX ? visible.minX : visible.midX,
                          y: visible.minY,
                          width: visible.width / 2,
                          height: visible.height)
        window.setFrame(half, display: true, animate: true)
    }

    @objc private func toggleFullScreen(_ sender: Any?) {
        mainWindow()?.toggleFullScreen(nil)
    }

    /// 关闭最后一个窗口时不退出（常驻 Dock）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 退出时，若服务器由我们启动且用户未要求保持，则同步停掉
    func applicationWillTerminate(_ notification: Notification) {
        let server = ServerManager.shared
        if server.startedByUs && !AppState.shared.keepServerOnQuit {
            server.stopAndWait()
        }
    }
}

extension Notification.Name {
    static let dshReloadRequested = Notification.Name("dshReloadRequested")
    static let dshWebViewLoaded = Notification.Name("dshWebViewLoaded")
}
