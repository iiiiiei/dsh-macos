import Foundation

/// 与 dsh-desktop-bridge 插件通信的客户端。
/// 该插件是 DSH 生态内的一个普通 Cordis 宿主插件，
/// 注册了 /api/desktop/status 与 /api/desktop/notify 两个路由。
@MainActor
final class BridgeClient {
    static let shared = BridgeClient()

    private var task: Task<Void, Never>?

    func start(appState: AppState, server: ServerManager) {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                guard server.status == .running else {
                    // 只在状态变化时赋值，避免无意义的重渲染导致 WebView 反复重载
                    if appState.bridgeConnected { appState.bridgeConnected = false }
                    if !appState.bridgeInfo.isEmpty { appState.bridgeInfo = "" }
                    try? await Task.sleep(for: .seconds(3))
                    continue
                }
                if let info = await fetchStatus(appState.url) {
                    if !appState.bridgeConnected { appState.bridgeConnected = true }
                    if appState.bridgeInfo != info { appState.bridgeInfo = info }
                    if let stats = await fetchStats(appState.url) {
                        if appState.stats != stats { appState.stats = stats }
                    } else if appState.stats != nil {
                        appState.stats = nil
                    }
                } else {
                    if appState.bridgeConnected { appState.bridgeConnected = false }
                    if !appState.bridgeInfo.isEmpty { appState.bridgeInfo = "" }
                    if appState.stats != nil { appState.stats = nil }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// 通过桥接插件触发 macOS 原生通知（插件内部用 osascript）
    func notify(title: String, message: String, appState: AppState) async -> Bool {
        var request = URLRequest(url: appState.url.appendingPathComponent("api/desktop/notify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "title": title,
            "message": message,
        ])
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Token 用量统计（桥接插件 /api/desktop/stats）
    private func fetchStats(_ base: URL) async -> TokenStats? {
        var request = URLRequest(url: base.appendingPathComponent("api/desktop/stats"))
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let usage = obj["usage"] as? [String: Any] else {
                return nil
            }
            return TokenStats(
                inputTokens: usage["inputTokens"] as? Int ?? 0,
                uncachedInputTokens: usage["uncachedInputTokens"] as? Int ?? 0,
                outputTokens: usage["outputTokens"] as? Int ?? 0,
                cacheReadTokens: usage["cacheReadTokens"] as? Int ?? 0,
                cacheWriteTokens: usage["cacheWriteTokens"] as? Int ?? 0,
                scope: obj["scope"] as? String ?? ""
            )
        } catch {
            return nil
        }
    }

    private func fetchStatus(_ base: URL) async -> String? {
        var request = URLRequest(url: base.appendingPathComponent("api/desktop/status"))
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let version = obj["version"] as? String ?? "?"
            let pid = obj["pid"] as? Int ?? 0
            let uptime = obj["uptimeMs"] as? Int ?? 0
            return "dsh v\(version) · pid \(pid) · 运行 \(uptime / 1000)s"
        } catch {
            return nil
        }
    }
}
