import SwiftUI
import AppKit

/// 供面板在任意场景中打开主窗口的桥（SwiftUI 的 openWindow 环境只在场景内可用）
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var openMain: (() -> Void)?
}

/// 迷你浮动面板：类似 Gemini 的弹出式面板，可拖动到任意位置
@MainActor
final class MiniPanelController {
    private var panel: MiniPanel?
    private let appState: AppState
    private let server: ServerManager
    private let statusItem: NSStatusItem

    init(appState: AppState, server: ServerManager, statusItem: NSStatusItem) {
        self.appState = appState
        self.server = server
        self.statusItem = statusItem
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel: MiniPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = MiniPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isMovableByWindowBackground = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: MiniPanelView(appState: appState, server: server))
            self.panel = panel
        }

        // 定位到菜单栏图标下方
        if let button = statusItem.button, let window = button.window {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            let x = buttonFrame.midX - panel.frame.width / 2
            let y = buttonFrame.minY - panel.frame.height - 8
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

/// 可接收键盘焦点的无边框面板（否则 TextField 无法输入）
final class MiniPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 面板内容
struct MiniPanelView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var server: ServerManager
    @State private var message = ""
    @State private var sendFeedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题行
            HStack(spacing: 6) {
                Image(systemName: "bolt.shield.fill")
                    .foregroundStyle(.blue)
                Text("DSH Desktop")
                    .fontWeight(.semibold)
                Spacer()
                Button("打开完整版") { openFullVersion() }
                    .controlSize(.small)
                Button {
                    NotificationCenter.default.post(name: .dshClosePanelRequested, object: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // 状态区
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(server.status.label)
                    .fontWeight(.medium)
                Spacer()
                if server.status == .running {
                    Button("停止") { server.stop() }
                        .controlSize(.small)
                }
            }

            // Token 统计（数据来自桥接插件 /api/desktop/stats）
            if let stats = appState.stats {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.scope)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        statItem("输入", formatTokens(stats.inputTokens), stats.cacheReadTokens > 0 ? "缓存命中 \(formatTokens(stats.cacheReadTokens))" : nil)
                        statItem("输出", formatTokens(stats.outputTokens), nil)
                        statItem("缓存未命中", formatTokens(stats.uncachedInputTokens), nil)
                    }
                }
                .font(.caption)
            }

            Divider()

            // 迷你输入：总是新建会话并发送
            TextField("给 DSH 发消息（将新建会话）…", text: $message)
                .textFieldStyle(.roundedBorder)
                .onSubmit { send() }

            if let sendFeedback {
                Text(sendFeedback)
                    .font(.caption)
                    .foregroundStyle(sendFeedback.hasPrefix("✅") ? .green : .red)
            }

            HStack {
                Button("发送", action: send)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button("前往开放平台") {
                    NSWorkspace.shared.open(URL(string: "https://platform.deepseek.com/")!)
                }
                .controlSize(.small)
                Button("测试通知") { sendTestNotification() }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 1))
        .shadow(radius: 12, y: 4)
    }

    private var statusColor: Color {
        switch server.status {
        case .running: return .green
        case .starting: return .yellow
        case .error: return .red
        default: return .gray
        }
    }

    private func statItem(_ title: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
            if let sub {
                Text(sub)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private func openFullVersion() {
        if let open = WindowOpener.shared.openMain {
            open()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func send() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sendFeedback = nil
        Task { @MainActor in
            do {
                let reply = try await ChatClient.shared.sendNewSession(text, appState: appState)
                sendFeedback = "✅ 已发送并新建会话"
                Log.info("chat: 发送成功，回复 \(reply.prefix(80))")
            } catch {
                sendFeedback = "❌ 发送失败：\(error.localizedDescription)"
                Log.info("chat: 发送失败 \(error.localizedDescription)")
            }
        }
    }

    private func sendTestNotification() {
        Task { @MainActor in
            let ok = await BridgeClient.shared.notify(
                title: "DSH Desktop",
                message: "来自 dsh-desktop-bridge 插件的原生通知 ✅",
                appState: appState
            )
            sendFeedback = ok ? "✅ 通知已触发（右上角查看）" : "❌ 桥接插件未激活：需要重启 DSH 服务器（见 README）"
        }
    }
}

extension Notification.Name {
    static let dshClosePanelRequested = Notification.Name("dshClosePanelRequested")
    static let dshReloadRequested = Notification.Name("dshReloadRequested")
}
