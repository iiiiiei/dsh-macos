// 生成 DSH Desktop 应用图标：蓝→青渐变圆角方块 + "DSH" 文字
// 用法: swift make-icon.swift <iconset目录>
import AppKit
import CoreText

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
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

func renderIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let s = CGFloat(size)

    // 圆角方块
    let inset = s * 0.05
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = s * 0.22
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // 蓝 → 青 渐变
    let colors = [
        NSColor(calibratedRed: 0.20, green: 0.36, blue: 1.00, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.92, alpha: 1).cgColor,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    // 网格线装饰（harness / 编织 意象）
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    ctx.setLineWidth(s * 0.008)
    let step = s / 5
    for i in 1...4 {
        let offset = step * CGFloat(i)
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + offset))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + offset))
        ctx.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
    }
    ctx.strokePath()

    ctx.resetClip()

    // "DSH" 文字
    let fontSize = s * 0.34
    guard let font = NSFont(name: "Helvetica-Bold", size: fontSize) else { return image }
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let string = NSAttributedString(string: "DSH", attributes: attrs)
    let line = CTLineCreateWithAttributedString(string)
    let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
    let x = (s - bounds.width) / 2 - bounds.minX
    let y = (s - bounds.height) / 2 - bounds.minY
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)

    return image
}

for spec in specs {
    let image = renderIcon(size: spec.size)
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
