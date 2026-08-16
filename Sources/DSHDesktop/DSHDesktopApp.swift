import SwiftUI
import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("applicationDidFinishLaunching")
        // 从终端直接运行二进制时也需要常规 Dock 应用行为
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 沉浸式窗口：等主窗口出现后设置透明标题栏 + 内容延伸（红绿灯悬浮、内容顶到顶）
        ensureFullSizeWindow()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil
        )

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
        ensureFullSizeWindow()
    }

    private func ensureFullSizeWindow() {
        guard !fullSizeApplied,
              let window = NSApp.windows.first(where: { $0.title.hasPrefix("DSH Desktop") }) else { return }
        fullSizeApplied = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        Log.info("window: fullSizeContentView 已应用（内容顶到顶）")
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
}
