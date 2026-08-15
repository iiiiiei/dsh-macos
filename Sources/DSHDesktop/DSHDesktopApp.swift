import SwiftUI
import AppKit

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

        MenuBarExtra {
            MenuBarView(appState: appState, server: server)
        } label: {
            // 用 bolt.shield 作为本应用的专属菜单栏图标（区别于其它应用的 bolt.fill）
            Image(systemName: server.status == .running ? "bolt.shield.fill" : "bolt.shield")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appState: appState, server: server)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("applicationDidFinishLaunching")
        // 从终端直接运行二进制时也需要常规 Dock 应用行为
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if CommandLine.arguments.contains("--selftest") {
            Task { @MainActor in
                await SelfTest.run(appState: AppState.shared, server: ServerManager.shared)
            }
        }
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
