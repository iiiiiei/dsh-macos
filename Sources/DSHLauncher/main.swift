import AppKit
import ServiceManagement

/// DSH Launcher —— 菜单栏常驻应用（GeminiAppLauncher 模式）
/// LSUIElement（无 Dock 图标），鲸鱼小图标常驻菜单栏；
/// 左键点击启动/唤起主应用 DSH Desktop；右键菜单提供操作。
final class LauncherApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // LSUIElement 保险
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.whaleIcon
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    /// 官方鲸鱼模板图标（18pt，自动适配深浅色）
    static let whaleIcon: NSImage = {
        let path = Bundle.main.path(forResource: "whale-icon", ofType: "png")
        let image = path.flatMap { NSImage(contentsOfFile: $0) }
            ?? NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "DSH Desktop")!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            launchMainApp()
        }
    }

    /// 启动/唤起主应用（已运行则激活）
    @objc private func launchMainApp() {
        let candidates = [
            URL(fileURLWithPath: "/Applications/DSH Desktop.app"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Desktop/dsh-macos/build/DSH Desktop.app"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            return
        }
        let alert = NSAlert()
        alert.messageText = "找不到 DSH Desktop"
        alert.informativeText = "请把 DSH Desktop.app 放到 /Applications 目录后重试。"
        alert.runModal()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "启动 DSH Desktop", action: #selector(launchMainApp), keyEquivalent: "")

        // 登录时自动启动：以 SMAppService.mainApp.status 为唯一真相
        let login = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 DSH Launcher", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置失败：\(error.localizedDescription)"
            alert.informativeText = "请确认 DSH Launcher 位于 /Applications 目录。"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = LauncherApp()
app.delegate = delegate
app.run()
