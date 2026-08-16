import Foundation

/// Appearance 协议：外观即 Overlay 集合。
/// - Official Appearance = Reference：对页面零覆盖（空 overlay）。
/// - 新 Appearance 必须基于 Official 叠加 Overlay，禁止复制/ Fork 官方页面。
/// - 关闭全部增强开关后必须回到 Official 行为（Fully Reversible）。
struct AppearanceManifest: Codable, Equatable {
    let id: String
    let name: String
    let version: String
    let compatibleOfficialHint: String?
    let officialVersion: String?
    let createdAt: String
}

/// Appearance 目录：当前仅实现 Official（默认）；Glass/Compact 等仅预留扩展点。
enum AppearanceCatalog {
    static let officialVersion = "0.1.0-rc.6"

    static let official = AppearanceManifest(
        id: "official",
        name: "Official",
        version: "1.0.0",
        compatibleOfficialHint: officialVersion,
        officialVersion: officialVersion,
        createdAt: "2026-08-16"
    )

    /// 预留：皮肤类 Appearance 未来在此注册（id → manifest + overlay 资源）
    static let available: [AppearanceManifest] = [official]

    static func manifest(id: String) -> AppearanceManifest? {
        available.first { $0.id == id }
    }

    static func isKnown(_ id: String) -> Bool {
        manifest(id: id) != nil
    }
}

/// 增强开关（UserDefaults 持久化，全部可关闭且关闭后回到 Official）
struct EnhancementToggles {
    /// 沉浸式标题栏（红绿灯悬浮、内容顶到顶）；默认开，关 = 系统标准标题栏
    var immersiveTitlebar: Bool
    /// 中文通俗说明 Overlay；默认开，关 = 官方原文
    var zhOverlay: Bool

    static let defaults = EnhancementToggles(immersiveTitlebar: true, zhOverlay: true)

    init(immersiveTitlebar: Bool, zhOverlay: Bool) {
        self.immersiveTitlebar = immersiveTitlebar
        self.zhOverlay = zhOverlay
    }

    init(defaults: UserDefaults) {
        immersiveTitlebar = defaults.object(forKey: "immersiveTitlebar") as? Bool ?? true
        zhOverlay = defaults.object(forKey: "zhOverlay") as? Bool ?? true
    }

    func save(_ defaults: UserDefaults) {
        defaults.set(immersiveTitlebar, forKey: "immersiveTitlebar")
        defaults.set(zhOverlay, forKey: "zhOverlay")
    }
}
