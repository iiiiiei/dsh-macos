import Foundation
import Combine

/// Token 用量统计（对齐 DSH 官方 StatsLine 口径，见 client-ui-conversation）
struct TokenStats: Equatable {
    var billedInputTokens: Int = 0     // 计费输入 = uncached + cacheRead + cacheWrite
    var outputTokens: Int = 0          // 输出
    var cacheHitPercent: Int?          // 缓存命中率 = round(cacheRead / billedInput * 100)
}

/// DSH 服务器状态
enum ServerStatus: Equatable {
    case unknown
    case stopped
    case starting
    case running
    case error(String)

    var label: String {
        switch self {
        case .unknown: return "检测中…"
        case .stopped: return "已停止"
        case .starting: return "启动中…"
        case .running: return "运行中"
        case .error(let message): return "错误：\(message)"
        }
    }

    var isActive: Bool {
        switch self {
        case .running, .starting: return true
        default: return false
        }
    }
}

/// 全局应用状态：设置 + 页面状态 + 桥接状态
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var status: ServerStatus = .unknown
    @Published var pageTitle: String = "DeepSeek Harness"
    @Published var pageLoaded: Bool = false
    @Published var bridgeConnected: Bool = false
    @Published var bridgeInfo: String = ""
    @Published var stats: TokenStats?
    /// GUI 当前打开的会话（WebView fetch 钩子上报）；nil = 未知，退回最近活跃
    @Published var currentSessionId: String?

    // MARK: - 设置（UserDefaults 持久化）

    @Published var port: Int
    @Published var serverCommand: String
    @Published var autoStartServer: Bool
    @Published var keepServerOnQuit: Bool

    private let defaults = UserDefaults.standard

    private init() {
        port = defaults.object(forKey: "port") as? Int ?? 3080
        serverCommand = defaults.string(forKey: "serverCommand") ?? "dsh --profile web"
        autoStartServer = defaults.object(forKey: "autoStartServer") as? Bool ?? true
        keepServerOnQuit = defaults.object(forKey: "keepServerOnQuit") as? Bool ?? false
    }

    var url: URL {
        // 设置里可能被填成 0 或越界值，clamp 到合法范围
        let p = min(max(port, 1), 65535)
        return URL(string: "http://127.0.0.1:\(p)")!
    }

    func saveSettings() {
        // 写回时同样 clamp，保证下次启动一致
        port = min(max(port, 1), 65535)
        defaults.set(port, forKey: "port")
        defaults.set(serverCommand, forKey: "serverCommand")
        defaults.set(autoStartServer, forKey: "autoStartServer")
        defaults.set(keepServerOnQuit, forKey: "keepServerOnQuit")
    }
}
