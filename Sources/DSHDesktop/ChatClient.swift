import Foundation

/// 迷你输入框的会话客户端：总是新建会话并发送消息。
/// 协议（经实测验证，详见 .research/dsh-protocol.md）：
///   POST /api/<method>，信封 {type:"client-request", rpcId, method, payload}
///   session.create → session.prompt（非流式，{accepted:true}）
///   → 轮询 session.history 拿 assistant/message 的 text
@MainActor
final class ChatClient {
    static let shared = ChatClient()

    /// 新建会话并发送消息，返回助手回复文本
    func sendNewSession(_ text: String, appState: AppState) async throws -> String {
        // 1) 新建会话（默认工作区）
        let createValue = try await rpc("session.create", payload: [:], appState: appState)
        guard let sessionId = createValue["sessionId"] as? String else {
            throw ChatError.bridgeFailed("session.create 响应缺少 sessionId")
        }

        // 2) 发送消息（mode: queue，立即受理，回复异步生成）
        _ = try await rpc("session.prompt", payload: [
            "sessionId": sessionId,
            "mode": "queue",
            "content": [["type": "text", "text": text]],
        ], appState: appState)

        // 3) 轮询 history 直到出现 assistant/message（长回复最多等 3 分钟）
        return try await waitForReply(sessionId: sessionId, appState: appState)
    }

    // MARK: - RPC

    private func rpc(_ method: String, payload: [String: Any], appState: AppState) async throws -> [String: Any] {
        var request = URLRequest(url: appState.url.appendingPathComponent("api/\(method)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-request",
            "rpcId": UUID().uuidString,
            "method": method,
            "payload": payload,
        ])
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ChatError.bridgeFailed("RPC \(method) HTTP 状态 \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [String: Any] else {
            throw ChatError.bridgeFailed("RPC \(method) 响应格式异常")
        }
        guard (result["ok"] as? Bool) == true else {
            let err = result["error"] as? [String: Any]
            throw ChatError.bridgeFailed("RPC \(method) 失败：\(err?["message"] as? String ?? "未知错误")")
        }
        return result["value"] as? [String: Any] ?? [:]
    }

    private func waitForReply(sessionId: String, appState: AppState) async throws -> String {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if let reply = try? await fetchLatestAssistantMessage(sessionId: sessionId, appState: appState),
               !reply.isEmpty {
                return reply
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
        throw ChatError.bridgeFailed("等待回复超时（180s）")
    }

    /// 取该会话最新的 assistant/message 文本；没有则返回 nil
    private func fetchLatestAssistantMessage(sessionId: String, appState: AppState) async throws -> String? {
        let value = try await rpc("session.history", payload: [
            "sessionId": sessionId,
            "maxMessages": 20,
        ], appState: appState)
        guard let entries = value["events"] as? [[String: Any]] else { return nil }
        var latest: String?
        for entry in entries {
            guard let event = entry["event"] as? [String: Any],
                  event["type"] as? String == "assistant/message",
                  let data = event["data"] as? [String: Any],
                  let message = data["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }
            let texts = content.compactMap { part -> String? in
                guard part["type"] as? String == "text", let t = part["text"] as? String else { return nil }
                return t
            }
            if !texts.isEmpty {
                latest = texts.joined(separator: "\n")
            }
        }
        return latest
    }
}

enum ChatError: LocalizedError {
    case bridgeFailed(String)

    var errorDescription: String? {
        switch self {
        case .bridgeFailed(let msg): return msg
        }
    }
}
