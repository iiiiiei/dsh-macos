import AppKit

/// 布局常量：对齐社区 DeepSeek Harness Desktop（方案1）公开约定。
/// 数值为目标量级（CSS/pt），用 AppKit 原生表达，禁止无注释魔法数散落。
enum DesktopLayout {
    /// 红绿灯位置对齐目标（方案1 trafficLightPosition 量级）；系统 inset 标题栏
    /// 原生位置已近似（x≈12-14, y≈18-20），不强行 setFrameOrigin 以免破坏系统外观
    static let trafficLightInsetX: CGFloat = 16
    static let trafficLightInsetY: CGFloat = 18

    /// 顶部拖拽带：红绿灯水平行整行（全宽），行高由红绿灯组件位置动态反推
    /// （contentLayoutRect 差值，实测 28pt；轴线在行内垂直居中）
    static let dragStripHeight: CGFloat = 32
    /// 主内容顶部 caption/标题预留（方案1：约 20 CSS px；网页无预留时仅作对齐参照）
    static let captionStripHeight: CGFloat = 20

    /// 折叠侧栏视觉总宽：以红绿灯系统默认绝对位置为锚（实测左缘 7、右缘 61、组宽 54）：
    /// 宽 = 红灯左距×2 + 组宽 = 68，使绿灯距右侧边框 = 红灯距左视窗框 = 7。
    /// 实际宽度由 overlay 消费注入的 --dsh-traffic-left/--dsh-traffic-width 动态计算，
    /// 此常量仅作文档参照。
    static let sidebarCollapsedWidth: CGFloat = 68
    /// 官方折叠轨宽度（56px 轨在 68px 侧栏内居中 → 轨中心 = 侧栏中心 = 黄灯中心 x=34）
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
        Log.info("dragstrip: mouseDown at=\(event.locationInWindow) origin=\(windowOrigin)")
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else {
            Log.info("dragstrip: mouseDragged but no window")
            return
        }
        let delta = NSPoint(x: event.locationInWindow.x - dragStart.x,
                            y: event.locationInWindow.y - dragStart.y)
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + delta.x,
                                      y: windowOrigin.y + delta.y))
        Log.info("dragstrip: mouseDragged at=\(event.locationInWindow) delta=\(delta) origin=\(window.frame.origin)")
    }

    override func mouseUp(with event: NSEvent) {
        Log.info("dragstrip: mouseUp at=\(event.locationInWindow)")
    }
}
