import SwiftUI
import AppKit
import Combine

@main
struct DSHDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var server = ServerManager.shared

    var body: some Scene {
        WindowGroup("DSH Desktop", id: "main") {
            ContentView(appState: appState, server: server)
        }
        .defaultSize(width: 1280, height: 840)
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

        Settings {
            SettingsView(appState: appState, server: server)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: MiniPanelController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("applicationDidFinishLaunching")
        // 从终端直接运行二进制时也需要常规 Dock 应用行为
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        setupStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(closePanel),
            name: .dshClosePanelRequested, object: nil
        )

        if CommandLine.arguments.contains("--selftest") {
            Task { @MainActor in
                await SelfTest.run(appState: AppState.shared, server: ServerManager.shared)
            }
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "DSH Desktop")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        panelController = MiniPanelController(appState: .shared, server: .shared, statusItem: item)

        // 状态图标随服务器状态切换（实心=运行中）
        ServerManager.shared.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                let name = status == .running ? "bolt.shield.fill" : "bolt.shield"
                self?.statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "DSH Desktop")
            }
            .store(in: &cancellables)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            panelController?.toggle()
        }
    }

    /// 右键菜单：保留完整菜单功能
    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开主窗口", action: #selector(openMainWindow), keyEquivalent: "")
        menu.addItem(withTitle: "在浏览器中打开", action: #selector(openInBrowser), keyEquivalent: "")
        menu.addItem(withTitle: "刷新页面", action: #selector(reloadPage), keyEquivalent: "")
        menu.addItem(.separator())
        let server = ServerManager.shared
        if server.status == .running {
            menu.addItem(withTitle: "停止服务器", action: #selector(stopServer), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "启动服务器", action: #selector(startServer), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "前往开放平台", action: #selector(openPlatform), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 DSH Desktop", action: #selector(quitApp), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - 菜单动作

    @objc private func openMainWindow() {
        if let open = WindowOpener.shared.openMain {
            open()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openInBrowser() {
        NSWorkspace.shared.open(AppState.shared.url)
    }

    @objc private func reloadPage() {
        NotificationCenter.default.post(name: .dshReloadRequested, object: nil)
    }

    @objc private func startServer() {
        ServerManager.shared.start()
    }

    @objc private func stopServer() {
        ServerManager.shared.stop()
    }

    @objc private func openPlatform() {
        NSWorkspace.shared.open(URL(string: "https://platform.deepseek.com/")!)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func closePanel() {
        panelController?.hide()
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
