import SwiftUI
import AppKit

@main
struct DSHDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var server = ServerManager.shared

    /// 官方鲸鱼模板图标（黑白自动适配，等价于网页版 favicon 的深浅色切换）。
    /// 图标 PNG 为 36x36 像素（2x），显示尺寸固定 18pt，避免菜单栏图标过大。
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
            }
        }

        // 原生菜单栏：状态 + token 统计 + 操作（官方鲸鱼模板图标，自动适配深浅色）
        MenuBarExtra {
            MenuBarView(appState: appState, server: server)
        } label: {
            Image(nsImage: DSHDesktopApp.whaleIcon)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appState: appState, server: server)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 仅菜单栏“退出”置位后允许终止（Dock/Cmd+Q 只关窗口不杀进程，与 Gemini 一致）
    private var quitRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self, selector: #selector(quitFromMenu),
            name: .dshQuitRequested, object: nil
        )
        Log.info("applicationDidFinishLaunching")
        // 从终端直接运行二进制时也需要常规 Dock 应用行为
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 等 SwiftUI 菜单系统稳定后补充窗口管理项，并周期确保不被重建清掉
        ensureWindowMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.ensureWindowMenu()
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.ensureWindowMenu() }
        }

        if CommandLine.arguments.contains("--selftest") {
            Task { @MainActor in
                await SelfTest.run(appState: AppState.shared, server: ServerManager.shared)
            }
        }
    }

    @objc private func quitFromMenu() {
        quitRequested = true
        NSApp.terminate(nil)
    }

    // MARK: - 窗口菜单补充（SwiftUI 默认只保留最小化/缩放/前置全部窗口/窗口列表，
    // macOS 15 的窗口管理项（居中/平铺/全屏）不会自动出现在菜单栏，这里补齐）

    private var windowMenuPatched = false

    /// 周期性幂等补丁：SwiftUI 可能在窗口状态变化时重建菜单，需反复确保
    private func ensureWindowMenu() {
        guard !windowMenuPatched || NSApp.windowsMenu?.items.contains(where: { $0.tag == 9001 }) != true else { return }
        windowMenuPatched = true
        guard let menu = NSApp.windowsMenu else { return }
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

    /// 拦截非显式退出：Dock“退出”/Cmd+Q 不结束进程（后台常驻菜单栏）
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitRequested ? .terminateNow : .terminateCancel
    }

    /// 关闭最后一个窗口时不退出（常驻菜单栏）
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
