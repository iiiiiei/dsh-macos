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
                if let stats = await fetchStats(appState.url) {
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
    /// 口径对齐 DSH 官方 StatsLine（client-ui-conversation）：
    ///   billedInput = uncached + cacheRead + cacheWrite
    ///   cacheHit% = round(cacheRead / billedInput * 100)
    ///   轮次/步骤来自 sessionStats 投影
    private func fetchStats(_ base: URL) async -> TokenStats? {
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

            // 解析每个会话的投影数据
            struct Row {
                var updatedAt: Int64
                var blank: Bool
                var usage: [String: Any]
                var stats: [String: Any]
            }
            var rows: [Row] = []
            for item in items {
                guard let projections = item["projections"] as? [String: Any],
                      let values = projections["values"] as? [String: Any] else { continue }
                let usage = (values["tokenUsage"] as? [String: Any]) ?? [:]
                let stats = (values["sessionStats"] as? [String: Any]) ?? [:]
                guard !usage.isEmpty || !stats.isEmpty else { continue }
                rows.append(Row(
                    updatedAt: (item["updatedAt"] as? NSNumber)?.int64Value ?? 0,
                    blank: item["blank"] as? Bool ?? true,
                    usage: usage,
                    stats: stats
                ))
            }
            guard !rows.isEmpty else { return nil }

            // 有非空会话 → 最近活跃会话的数据；否则今日所有会话聚合
            let active = rows.filter { !$0.blank }.max { $0.updatedAt < $1.updatedAt }
            let startOfToday = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000)

            let usage: [String: Any]
            let stats: [String: Any]
            let scope: String
            if let active {
                usage = active.usage
                stats = active.stats
                scope = "当前会话"
            } else {
                var usageTotals: [String: Int] = [:]
                var turnTotal = 0, stepTotal = 0
                for row in rows where row.updatedAt >= startOfToday {
                    for key in ["uncachedInputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens"] {
                        usageTotals[key, default: 0] += (row.usage[key] as? NSNumber)?.intValue ?? 0
                    }
                    turnTotal += (row.stats["turns"] as? NSNumber)?.intValue ?? 0
                    stepTotal += (row.stats["steps"] as? NSNumber)?.intValue ?? 0
                }
                usage = usageTotals
                stats = ["turns": turnTotal, "steps": stepTotal]
                scope = "今日总计"
            }

            // 官方口径换算
            let uncached = (usage["uncachedInputTokens"] as? NSNumber)?.intValue ?? 0
            let cacheRead = (usage["cacheReadTokens"] as? NSNumber)?.intValue ?? 0
            let cacheWrite = (usage["cacheWriteTokens"] as? NSNumber)?.intValue ?? 0
            let output = (usage["outputTokens"] as? NSNumber)?.intValue ?? 0
            let billed = uncached + cacheRead + cacheWrite
            let hitPercent = billed == 0 ? nil : Int((Double(cacheRead) / Double(billed) * 100).rounded())

            return TokenStats(
                billedInputTokens: billed,
                outputTokens: output,
                cacheHitPercent: hitPercent,
                turns: (stats["turns"] as? NSNumber)?.intValue ?? 0,
                steps: (stats["steps"] as? NSNumber)?.intValue ?? 0,
                scope: scope
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
