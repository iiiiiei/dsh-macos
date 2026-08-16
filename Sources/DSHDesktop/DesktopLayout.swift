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

    /// 折叠侧栏宽度对齐目标（方案1：90 CSS px；官方折叠轨约 56px 在其中居中）
    static let sidebarCollapsedWidth: CGFloat = 90
    /// 官方折叠轨宽度（居中基准，方案1 表述）
    static let sidebarRailWidth: CGFloat = 56

    /// 红绿灯行高估算（用于侧栏顶部避让；实际以 standardWindowButton frame 动态计算优先）
    static let trafficLightRowHeight: CGFloat = 28
}

/// 透明拖拽带：红绿灯右侧约 32pt 宽 × 32pt 高，按下拖动移动窗口。
/// 原生等价 Electron `app-region: drag`；覆盖区域为红绿灯右侧窄条，
/// 不覆盖主内容顶栏（避免挡按钮/链接/输入框的点击）。
final class DragStripView: NSView {
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // 潜在拖动开始；未拖动的单击被吞（区域为红绿灯右侧窄条，下方为页面边缘）
        window?.performDrag(with: event)
    }
}
