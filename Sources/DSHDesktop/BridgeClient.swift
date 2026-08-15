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
                } else {
                    if appState.bridgeConnected { appState.bridgeConnected = false }
                    if !appState.bridgeInfo.isEmpty { appState.bridgeInfo = "" }
                }
                // Token 统计：直连 RPC，不依赖桥接插件激活
                if let stats = await fetchStats(appState.url, currentSessionId: appState.currentSessionId) {
                    if appState.stats != stats { appState.stats = stats }
                } else if appState.stats != nil {
                    appState.stats = nil
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

    /// Token 用量统计：直连 RPC session.list。
    /// 口径对齐 DSH 官方 StatsLine：billedInput = uncached + cacheRead + cacheWrite，
    /// 缓存命中率 = round(cacheRead / billedInput * 100)。
    /// 优先跟随 GUI 当前打开的会话（WebView fetch 钩子上报）；未知时退回最近活跃会话；
    /// 无任何会话时显示今日聚合。
    private func fetchStats(_ base: URL, currentSessionId: String?) async -> TokenStats? {
        var request = URLRequest(url: base.appendingPathComponent("api/session.list"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "type": "client-request",
            "rpcId": UUID().uuidString,
            "method": "session.list",
            "payload": [String: Any](),
        ])
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = obj["result"] as? [String: Any],
                  (result["ok"] as? Bool) == true,
                  let value = result["value"] as? [String: Any],
                  let items = value["items"] as? [[String: Any]] else {
                return nil
            }

            struct Row {
                var sessionId: String
                var updatedAt: Int64
                var blank: Bool
                var usage: [String: Any]
            }
            var rows: [Row] = []
            for item in items {
                guard let sessionId = item["sessionId"] as? String,
                      let projections = item["projections"] as? [String: Any],
                      let values = projections["values"] as? [String: Any],
                      let usage = values["tokenUsage"] as? [String: Any] else { continue }
                rows.append(Row(
                    sessionId: sessionId,
                    updatedAt: (item["updatedAt"] as? NSNumber)?.int64Value ?? 0,
                    blank: item["blank"] as? Bool ?? true,
                    usage: usage
                ))
            }
            guard !rows.isEmpty else { return nil }

            // 1) GUI 当前打开的会话（精确跟随）
            if let current = currentSessionId,
               let row = rows.first(where: { $0.sessionId == current }) {
                return makeStats(row.usage)
            }
            // 2) 最近活跃的非空会话
            if let active = rows.filter({ !$0.blank }).max(by: { $0.updatedAt < $1.updatedAt }) {
                return makeStats(active.usage)
            }
            // 3) 今日聚合
            let startOfToday = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000)
            var totals: [String: Int] = [:]
            for row in rows where row.updatedAt >= startOfToday {
                for key in ["uncachedInputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens"] {
                    totals[key, default: 0] += (row.usage[key] as? NSNumber)?.intValue ?? 0
                }
            }
            return makeStats(totals)
        } catch {
            return nil
        }
    }

    /// 官方口径换算
    private func makeStats(_ usage: [String: Any]) -> TokenStats {
        let uncached = (usage["uncachedInputTokens"] as? NSNumber)?.intValue ?? 0
        let cacheRead = (usage["cacheReadTokens"] as? NSNumber)?.intValue ?? 0
        let cacheWrite = (usage["cacheWriteTokens"] as? NSNumber)?.intValue ?? 0
        let output = (usage["outputTokens"] as? NSNumber)?.intValue ?? 0
        let billed = uncached + cacheRead + cacheWrite
        let hit = billed == 0 ? nil : Int((Double(cacheRead) / Double(billed) * 100).rounded())
        return TokenStats(billedInputTokens: billed, outputTokens: output, cacheHitPercent: hit)
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
