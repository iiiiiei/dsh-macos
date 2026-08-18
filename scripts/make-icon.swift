// 生成 DSH Desktop 应用图标（官方鲸鱼 logo 版）
// 用法: swift make-icon.swift <whale.svg> <iconset目录> <菜单栏模板png输出>
import AppKit

guard CommandLine.arguments.count >= 4 else {
    FileHandle.standardError.write("usage: make-icon.swift <whale.svg> <iconset> <menubar.png>\n".data(using: .utf8)!)
    exit(1)
}
let svgPath = CommandLine.arguments[1]
let outputDir = CommandLine.arguments[2]
let menubarPng = CommandLine.arguments[3]

guard let svg = NSImage(contentsOfFile: svgPath) else {
    FileHandle.standardError.write("cannot load \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// iconutil 规范的文件名 → 像素尺寸
let specs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

/// 以精确像素尺寸渲染到位图（显式 NSBitmapImageRep，避免 lockFocus 在 Retina 下的 2x 膨胀）
func renderPixels(size: Int, draw: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size) // 1x 逻辑尺寸，像素即声明值
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext, CGFloat(size))
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// 应用图标：白色圆角底 + 黑色鲸鱼（还原官方白底黑鲸风格）。
/// macOS 图标规范：圆角 ~21%、内容留边 ~4.5%、鲸鱼居中约 58%（内容落在系统安全区内）。
func renderAppIcon(size: Int) -> NSImage {
    let rep = renderPixels(size: size) { ctx, s in
        let inset = s * 0.045
        let bgRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let corner = s * 0.21
        let shape = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // 纯白底（浅色 Dock 下清晰，官方 iOS 图标同款）
        ctx.addPath(shape)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()

        // 黑色鲸鱼：居中，高度约占 58%，四周留白均衡
        let whaleSize = s * 0.58
        let whaleRect = NSRect(
            x: (s - whaleSize) / 2,
            y: (s - whaleSize) / 2,
            width: whaleSize,
            height: whaleSize
        )
        svg.draw(in: whaleRect)
    }
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

for spec in specs {
    let image = renderAppIcon(size: spec.size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to render \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: "\(outputDir)/\(spec.name)")
    try png.write(to: url)
    print("wrote \(url.path) (\(spec.size)x\(spec.size))")
}

// 菜单栏模板图标：36x36 黑色鲸鱼（alpha 形状，模板渲染自动适配深浅色）
let menuRep = renderPixels(size: 36) { ctx, s in
    svg.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
}
menuRep.size = NSSize(width: 18, height: 18)
guard let png = menuRep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render menubar icon\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: menubarPng))
print("wrote \(menubarPng) (menubar template 36px/18pt)")
