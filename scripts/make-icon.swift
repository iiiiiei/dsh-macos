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

guard let svgData = try? Data(contentsOf: URL(fileURLWithPath: svgPath)),
      var svgString = String(data: svgData, encoding: .utf8) else {
    FileHandle.standardError.write("cannot load \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}
// 应用图标使用白色鲸鱼；菜单栏模板仍用原始黑色。
svgString = svgString.replacingOccurrences(of: "fill=\"#000\"", with: "fill=\"#FFFFFF\"")
guard let whiteSvgData = svgString.data(using: .utf8),
      let whiteSvg = NSImage(data: whiteSvgData) else {
    FileHandle.standardError.write("cannot create white whale image\n".data(using: .utf8)!)
    exit(1)
}
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

/// 应用图标：macOS Big Sur 风格圆角 + 深色渐变背景 + 白色鲸鱼。
/// 保留鲸鱼图案内容，仅改变背景呈现方式以融入 macOS Dock。
func renderAppIcon(size: Int) -> NSImage {
    let rep = renderPixels(size: size) { ctx, s in
        let corner = s * 0.224 // Big Sur 圆角
        // macOS 图标规范：内容不要顶格，留出约 8% 边距，
        // 这样 Dock 中行高/列宽才和其他原生 App 一致。
        let inset = s * 0.08
        let bgRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let shape = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // 1. 投影：让图标在 Dock/桌面有层次感
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02),
                      blur: s * 0.05,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(shape)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. 渐变背景（深灰到稍浅的深灰，类似系统 App 图标）
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.22, alpha: 1.0).cgColor,
                NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).cgColor
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
        ctx.restoreGState()

        // 3. 白色鲸鱼：居中，高度约占 55%
        let whaleSize = s * 0.55
        let whaleRect = NSRect(
            x: (s - whaleSize) / 2,
            y: (s - whaleSize) / 2,
            width: whaleSize,
            height: whaleSize
        )
        whiteSvg.draw(in: whaleRect)
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

// 菜单栏模板图标：36x36 像素（逻辑 18pt，@2x），黑色鲸鱼 alpha 形状
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
