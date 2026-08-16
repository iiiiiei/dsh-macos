import AppKit

/// 布局常量：对齐社区 DeepSeek Harness Desktop（方案1）公开约定。
/// 数值为目标量级（CSS/pt），用 AppKit 原生表达，禁止无注释魔法数散落。
enum DesktopLayout {
    /// 红绿灯位置对齐目标（方案1 trafficLightPosition 量级）；系统 inset 标题栏
    /// 原生位置已近似（x≈12-14, y≈18-20），不强行 setFrameOrigin 以免破坏系统外观
    static let trafficLightInsetX: CGFloat = 16
    static let trafficLightInsetY: CGFloat = 18

    /// 红绿灯右侧透明拖拽带宽度（方案1：约 32 CSS px）
    static let dragStripWidth: CGFloat = 32
    /// 顶部拖拽带高度（方案1：约 32 CSS px，覆盖 20px 标题预留量级）
    static let dragStripHeight: CGFloat = 32
    /// 主内容顶部 caption/标题预留（方案1：约 20 CSS px；网页无预留时仅作对齐参照）
    static let captionStripHeight: CGFloat = 20

    /// 折叠侧栏宽度：以红绿灯系统默认绝对位置为锚（左缘 12 × 2 + 组宽 54 = 78），
    /// 使红绿灯在折叠侧栏内水平居中（方案1 原目标 90，按用户反馈以红绿灯为锚调整）
    static let sidebarCollapsedWidth: CGFloat = 78
    /// 官方折叠轨宽度（居中基准，方案1 表述）
    static let sidebarRailWidth: CGFloat = 56

    /// 红绿灯行高估算（用于侧栏顶部避让；实际以 standardWindowButton frame 动态计算优先）
    static let trafficLightRowHeight: CGFloat = 28
}

/// 透明拖拽带：红绿灯水平行整行（全宽），按住拖动移动窗口。
/// 原生等价 Electron `app-region: drag`；用 mouseDragged 手动移动窗口
/// （performDrag(with:) 在非系统标题栏场景实测无效）。
final class DragStripView: NSView {
    private var dragStart: NSPoint = .zero
    private var windowOrigin: NSPoint = .zero

    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        windowOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let delta = NSPoint(x: event.locationInWindow.x - dragStart.x,
                            y: event.locationInWindow.y - dragStart.y)
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + delta.x,
                                      y: windowOrigin.y + delta.y))
    }
}
