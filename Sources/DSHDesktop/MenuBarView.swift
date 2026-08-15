import SwiftUI
import AppKit

/// 菜单栏（状态栏）视图
struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var server: ServerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 应用名标识：与其它闪电图标区分开
            HStack(spacing: 6) {
                Image(systemName: "bolt.shield.fill")
                    .foregroundStyle(.blue)
                Text("DSH Desktop")
                    .fontWeight(.semibold)
            }
            .padding(.vertical, 2)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(server.status.label)
                    .fontWeight(.medium)
            }
            .padding(.vertical, 4)

            Divider()

            Button("打开主窗口") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("在浏览器中打开") {
                NSWorkspace.shared.open(appState.url)
            }
            Button("刷新页面") {
                NotificationCenter.default.post(name: .dshReloadRequested, object: nil)
            }

            Divider()

            if server.status == .running {
                Button("停止服务器") { server.stop() }
            } else {
                Button("启动服务器") { server.start() }
            }

            Divider()

            if appState.bridgeConnected {
                Button("发送测试通知（桥接插件）") {
                    Task {
                        _ = await BridgeClient.shared.notify(
                            title: "DSH Desktop",
                            message: "来自 dsh-desktop-bridge 插件的原生通知 ✅",
                            appState: appState
                        )
                    }
                }
            } else {
                Text("桥接插件未激活（见 README）")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Button("设置…") { openSettings() }
            Button("退出 DSH Desktop") { NSApp.terminate(nil) }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch server.status {
        case .running: return .green
        case .starting: return .yellow
        case .error: return .red
        default: return .gray
        }
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

extension Notification.Name {
    static let dshReloadRequested = Notification.Name("dshReloadRequested")
}
