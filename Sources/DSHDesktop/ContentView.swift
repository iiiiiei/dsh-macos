import SwiftUI

/// 主窗口内容：服务器未就绪时显示状态面板，就绪后内嵌 Web GUI
struct ContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var server: ServerManager

    var body: some View {
        Group {
            switch server.status {
            case .running:
                HarnessWebView(url: appState.url) { state in
                    switch state {
                    case .loaded(let title):
                        appState.pageTitle = title
                        if !appState.pageLoaded { appState.pageLoaded = true }
                    case .loading:
                        // 幂等：仅在值变化时赋值，避免触发无意义的重渲染
                        if appState.pageLoaded { appState.pageLoaded = false }
                    case .failed:
                        if appState.pageLoaded { appState.pageLoaded = false }
                    }
                }
            case .starting, .unknown:
                StatusPanel(status: server.status, onStart: { server.start() }, spinner: true)
            case .stopped, .error:
                StatusPanel(status: server.status, onStart: { server.start() }, spinner: false)
            }
        }
        .frame(minWidth: 600, minHeight: 360)
        // 顶到顶：会话顶部栏需要覆盖透明拖拽行；侧栏单独由 desktop-layout.js
        // 预留标题行，不把整个会话区整体下推。
        .ignoresSafeArea()
        // 顶到顶：内容忽略 safe area（否则 SwiftUI 会把 WebView 从标题栏下方排布，
        // 顶部露出窗口背景色横条）
        .onAppear {
            bootstrap()
        }
        .onChange(of: appState.pageTitle) { newTitle in
            updateWindowTitle(newTitle)
        }
    }

    /// 启动时：attach 已有实例 → 按设置自动启动 → 启动桥接轮询
    private func bootstrap() {
        Task {
            await server.attach()
            if appState.autoStartServer && !server.status.isActive {
                server.start()
            }
            BridgeClient.shared.start(appState: appState, server: server)
        }
    }

    private func updateWindowTitle(_ title: String) {
        // 优先 keyWindow（避免把标题写到设置窗口上）
        let window = NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.title.hasPrefix("DSH Desktop") })
            ?? NSApp.windows.first(where: { $0.isVisible })
        guard let window else { return }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        window.title = clean.isEmpty ? "DSH Desktop" : "DSH Desktop — \(clean)"
    }
}

/// 服务器未运行时的状态面板
struct StatusPanel: View {
    let status: ServerStatus
    let onStart: () -> Void
    let spinner: Bool

    var body: some View {
        VStack(spacing: 14) {
            if spinner {
                ProgressView()
                    .controlSize(.small)
            }
            Image(systemName: "server.rack")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("DeepSeek Harness 服务器")
                .font(.title2)
                .fontWeight(.semibold)
            Text(status.label)
                .foregroundStyle(.secondary)
            if case .starting = status {
                Text("正在冷启动 DSH 服务器（首次约需数秒）…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if case .error = status {
                Text("请检查启动命令与端口设置")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button(action: onStart) {
                Label("启动服务器", systemImage: "play.fill")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(status == .starting)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
