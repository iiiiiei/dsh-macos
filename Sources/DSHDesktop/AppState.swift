import Foundation
import Combine

/// Token 用量统计（对齐 DSH 官方 StatsLine 口径，见 client-ui-conversation）

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
    /// GUI 当前打开的会话（WebView fetch 钩子上报）；nil = 未知，退回最近活跃

    // MARK: - 窗口增强（持久化）

    @Published var immersiveTitlebar: Bool = true

    // MARK: - 设置（UserDefaults 持久化）

    /// DSH 后端固定监听端口（不可改，避免误改导致连不上后端）
    static let defaultPort = 3080
    @Published var serverCommand: String
    @Published var autoStartServer: Bool
    @Published var keepServerOnQuit: Bool

    private let defaults = UserDefaults.standard

    private init() {
        serverCommand = defaults.string(forKey: "serverCommand") ?? "dsh --profile web"
        autoStartServer = defaults.object(forKey: "autoStartServer") as? Bool ?? true
        keepServerOnQuit = defaults.object(forKey: "keepServerOnQuit") as? Bool ?? false
        immersiveTitlebar = defaults.object(forKey: "immersiveTitlebar") as? Bool ?? true
    }

    var url: URL {
        return URL(string: "http://127.0.0.1:\(Self.defaultPort)")!
    }

    func saveSettings() {
        defaults.set(serverCommand, forKey: "serverCommand")
        defaults.set(autoStartServer, forKey: "autoStartServer")
        defaults.set(keepServerOnQuit, forKey: "keepServerOnQuit")
        defaults.set(immersiveTitlebar, forKey: "immersiveTitlebar")
    }
}
