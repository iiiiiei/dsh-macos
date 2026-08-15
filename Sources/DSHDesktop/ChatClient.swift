import Foundation

/// 迷你输入框的会话客户端：总是新建会话并发送消息。
/// 协议细节（RPC envelope / 桥接端点）由 .research/dsh-protocol.md 确定。
@MainActor
final class ChatClient {
    static let shared = ChatClient()

    /// 新建一个会话并发送消息，返回助手回复文本。
    /// 优先走桥接插件的 /api/desktop/chat（宿主侧代发，简单可靠）；
    /// 桥接未激活时降级为直连 DSH RPC。
    func sendNewSession(_ text: String, appState: AppState) async throws -> String {
        // 1) 尝试桥接插件
        if appState.bridgeConnected {
            if let reply = try? await viaBridge(text, appState: appState) {
                return reply
            }
        }
        // 2) 降级：直连 DSH RPC（session.create + session.prompt）
        return try await viaRPC(text, appState: appState)
    }

    // MARK: - 桥接插件路径（/api/desktop/chat，插件新增端点）

    private func viaBridge(_ text: String, appState: AppState) async throws -> String {
        var request = URLRequest(url: appState.url.appendingPathComponent("api/desktop/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["content": text])
        request.timeoutInterval = 180 // 长回复可能耗时
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ChatError.bridgeFailed("桥接端点返回非 200")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = obj["reply"] as? String else {
            throw ChatError.bridgeFailed("桥接端点响应格式异常")
        }
        return reply
    }

    // MARK: - 直连 RPC 路径（协议见 .research/dsh-protocol.md）

    private func viaRPC(_ text: String, appState: AppState) async throws -> String {
        throw ChatError.rpcNotReady("直连 RPC 协议待接入（桥接插件激活后自动使用）")
    }
}

enum ChatError: LocalizedError {
    case bridgeFailed(String)
    case rpcNotReady(String)

    var errorDescription: String? {
        switch self {
        case .bridgeFailed(let msg): return msg
        case .rpcNotReady(let msg): return msg
        }
    }
}
