import SwiftUI
import AppKit

/// 菜单栏（macOS 原生下拉菜单）：状态 + token 统计（纯文本）+ 操作项
struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var server: ServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 状态行
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(server.status.label)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.vertical, 4)

            // Token 统计（竖向排列，字号与菜单其它项一致，对齐官方口径）
            if let stats = appState.stats {
                VStack(alignment: .leading, spacing: 2) {
                    Text("输入 \(formatTokens(stats.billedInputTokens))")
                        .monospacedDigit()
                    Text("输出 \(formatTokens(stats.outputTokens))")
                        .monospacedDigit()
                    if let hit = stats.cacheHitPercent {
                        Text("缓存命中 \(hit)%")
                            .monospacedDigit()
                    }
                }
                .padding(.bottom, 4)
            }

            Divider()

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
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Button("前往开放平台") {
                NSWorkspace.shared.open(URL(string: "https://platform.deepseek.com/")!)
            }
            Button("退出 DSH Desktop") {
                NotificationCenter.default.post(name: .dshQuitRequested, object: nil)
            }
        }
        .padding(.vertical, 6)
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private var statusColor: Color {
        switch server.status {
        case .running: return .green
        case .starting: return .yellow
        case .error: return .red
        default: return .gray
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

extension Notification.Name {
    static let dshReloadRequested = Notification.Name("dshReloadRequested")
    static let dshQuitRequested = Notification.Name("dshQuitRequested")
}
