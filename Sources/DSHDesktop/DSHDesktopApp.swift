import SwiftUI
import AppKit
import WebKit
import UserNotifications

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

                Button("发送测试通知") {
                    Task { @MainActor in
                        await sendTestNotification()
                    }
                }
            }
        }

        Settings {
            SettingsView(appState: appState, server: server)
        }
    }

    /// 原生通知（UserNotifications）：归属 DSH Desktop，
    /// 系统设置 → 通知 里可见可管；首次发送时请求授权
    private func sendTestNotification() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "DSH Desktop"
        content.body = "原生通知通道正常 ✅"
        try? await center.add(UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        ))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var fullSizeApplied = false
    private var dragStrip: DragStripView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 从终端直接运行二进制时也需要常规 Dock 应用行为
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // 原生通知：应用在前台时也显示横幅
        UNUserNotificationCenter.current().delegate = self

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
            Task { @MainActor [weak self] in
                self?.applyWindowEnhancements()
            }
        }
        // 窗口尺寸变化时跟随拖拽带（Low Memory：事件驱动，无轮询）
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            let windowNumber = window.windowNumber
            Task { @MainActor [weak self] in
                guard let window = NSApp.window(withWindowNumber: windowNumber),
                      window.title.hasPrefix("DSH Desktop"),
                      AppState.shared.immersiveTitlebar else { return }
                self?.layoutDragStrip(window)
            }
        }
        // 网页加载完成后把拖拽带重新置顶（SwiftUI 晚插入的 WKWebView 会盖住先加入的拖拽带）
        NotificationCenter.default.addObserver(
            forName: .dshWebViewLoaded, object: nil, queue: .main
        ) { [weak self] notification in
            guard let webView = notification.object as? WKWebView,
                  let windowNumber = webView.window?.windowNumber else { return }
            Task { @MainActor [weak self] in
                guard let window = NSApp.window(withWindowNumber: windowNumber),
                      AppState.shared.immersiveTitlebar else { return }
                self?.installDragStrip(in: window)
            }
        }

        // 窗口菜单补充：每次打开前确保系统级控制项在位
        ensureWindowMenu()
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
                alignTrafficLights(in: window)
            } else {
                window.titlebarAppearsTransparent = false
                window.titleVisibility = .visible
                window.styleMask.remove(.fullSizeContentView)
                window.titlebarSeparatorStyle = .automatic
            }
            fullSizeApplied = true
            // 拖拽带只属于沉浸式标题栏；关闭沉浸式时恢复原生标题栏的点击区域。
            if immersive {
                installDragStrip(in: window)
            } else {
                removeDragStrip(from: window)
            }
            // 红绿灯使用 Codex/参考外壳中心锚点；折叠侧栏是独立的 Web 外壳规则。
        }
        if fullSizeApplied {
        }
        // 运行时几何断言：contentView 是否覆盖到窗口顶部（用于自动验证）
        if let window = NSApp.windows.first(where: { $0.title.hasPrefix("DSH Desktop") }) {
            let wf = window.frame
            let cf = window.contentView?.frame ?? .zero
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
    }

    /// NSMenuDelegate：窗口菜单每次打开前确保补充项在位
    func menuWillOpen(_ menu: NSMenu) {
        ensureWindowMenu()
    }

    // MARK: - 拖拽带（方案1：红绿灯右侧约 32 CSS px 透明拖拽）

    /// 将系统按钮组整体平移到用户约定的中心锚点 (23, 23)，不改按钮相对位置。
    ///
    /// 红灯左上角距离窗口左/上边缘等量；按钮组整体平移，保留 AppKit
    /// 自己决定的按钮尺寸与间距。
    private func alignTrafficLights(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let host = close.superview else { return }

        let buttons = [close, mini, zoom]
        let closeFrame = close.frame
        let horizontalOffsets = buttons.map { $0.frame.minX - closeFrame.minX }
        let targetMidY = host.isFlipped
            ? DesktopLayout.trafficLightCenterY
            : host.bounds.height - DesktopLayout.trafficLightCenterY
        let targetCloseMinX = DesktopLayout.trafficLightCenterX - closeFrame.width / 2

        for (button, offset) in zip(buttons, horizontalOffsets) {
            var frame = button.frame
            frame.origin.x = targetCloseMinX + offset
            frame.origin.y = targetMidY - frame.height / 2
            button.frame = frame
        }

    }

    private func installDragStrip(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        if let strip = dragStrip, strip.window === window {
            // 拖拽带必须始终是 contentView 的最后一个子视图（最上层）：
            // SwiftUI 在服务器就绪后插入的 WKWebView 会排到拖拽带之上，
            // 导致拖拽带永远收不到鼠标事件（不可拖拽的根因）。
            if contentView.subviews.last !== strip {
                strip.removeFromSuperview()
                contentView.addSubview(strip)
            }
            layoutDragStrip(window)
            return
        }
        let strip = DragStripView(frame: .zero)
        contentView.addSubview(strip)
        dragStrip = strip
        layoutDragStrip(window)
    }

    private func removeDragStrip(from window: NSWindow) {
        guard let strip = dragStrip, strip.window === window else { return }
        strip.removeFromSuperview()
        dragStrip = nil
    }

    /// 拖拽带：覆盖顶部透明行，行高 = 红绿灯水平中心线 × 2 = 46。
    /// 红绿灯在该行内垂直居中（中心 y=23），左右留出系统按钮/右侧控件安全区。
    private func layoutDragStrip(_ window: NSWindow) {
        guard let strip = dragStrip, let contentView = window.contentView else { return }
        alignTrafficLights(in: window)
        let rowHeight = DesktopLayout.dragStripHeight
        let y = contentView.isFlipped
            ? 0
            : contentView.bounds.height - rowHeight
        let safeWidth = DesktopLayout.trafficLightSafeWidth
        let rightSafeWidth = min(
            DesktopLayout.topControlsSafeWidth,
            max(0, contentView.bounds.width - safeWidth)
        )
        strip.frame = NSRect(
            x: safeWidth,
            y: y,
            width: max(0, contentView.bounds.width - safeWidth - rightSafeWidth),
            height: rowHeight
        )
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


// 原生通知：应用在前台时也显示横幅（默认前台不弹）
extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
