import SwiftUI
import AppKit

/// 供菜单栏/迷你窗口在任意场景中打开主窗口的桥（SwiftUI 的 openWindow 环境只在场景内可用）
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var openMain: (() -> Void)?
}

/// 迷你对话窗口：一个 dsh 风格的迷你输入框。
/// 从菜单栏"迷你对话…"打开；DSH 未运行时打开会自动在后台拉起服务器。
@MainActor
final class MiniChatController {
    private var panel: MiniChatPanel?
    private let appState: AppState
    private let server: ServerManager

    init(appState: AppState, server: ServerManager) {
        self.appState = appState
        self.server = server
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 打开迷你对话：dsh 未运行则先后台启动
    func open() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = MiniChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "DSH Desktop — 迷你对话"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: MiniChatView(appState: appState, server: server))
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // dsh 未运行：后台拉起（不打断输入框使用）
        switch server.status {
        case .stopped, .unknown, .error:
            server.start()
        default:
            break
        }
    }

    func close() {
        panel?.close()
    }
}

/// 可接收键盘焦点的面板
final class MiniChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// dsh 风格的迷你输入框：输入 → 新建会话发送 → 窗口内显示回复
struct MiniChatView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var server: ServerManager
    @State private var message = ""
    @State private var sending = false
    @State private var reply: String?
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 服务器状态行（未运行时提示自动启动）
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // 回复区（发送后显示）
            if sending {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在生成回复…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let reply {
                ScrollView {
                    Text(reply)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                if let feedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // dsh 风格的输入框 + 发送
            HStack(spacing: 8) {
                TextField("发消息给 DSH…", text: $message)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send() }
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }

    private var statusColor: Color {
        switch server.status {
        case .running: return .green
        case .starting: return .yellow
        case .error: return .red
        default: return .gray
        }
    }

    private var statusText: String {
        switch server.status {
        case .running: return "DSH 运行中 · 消息将新建会话"
        case .starting: return "正在后台启动 DSH 服务器…"
        case .error(let msg): return "服务器错误：\(msg)"
        case .stopped, .unknown: return "DSH 未运行，发送时将自动启动"
        }
    }

    private func send() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        reply = nil
        feedback = nil
        Task { @MainActor in
            // 服务器未就绪：等待后台启动完成（最多 30s）
            let ready = await ensureServerReady()
            guard ready else {
                sending = false
                feedback = "服务器启动失败，请检查设置"
                return
            }
            do {
                let response = try await ChatClient.shared.sendNewSession(text, appState: appState)
                reply = response
                message = ""
            } catch {
                feedback = "发送失败：\(error.localizedDescription)"
            }
            sending = false
        }
    }

    /// 等待服务器就绪（未运行时由 MiniChatController 触发启动）
    private func ensureServerReady() async -> Bool {
        guard server.status != .running else { return true }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if server.status == .running { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return server.status == .running
    }
}

extension Notification.Name {
    static let dshReloadRequested = Notification.Name("dshReloadRequested")
}
