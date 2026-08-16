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

/// 应用图标：白色圆角底 + 黑色鲸鱼（参考官方 iOS 应用图标：白底、鲸鱼居中、留白均衡）
func renderAppIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let s = CGFloat(size)

    // 白底全幅（不画圆角方块，圆角遮罩交给 macOS 系统），内容占比接近原生应用
    NSColor.white.setFill()
    CGRect(x: 0, y: 0, width: s, height: s).fill()

    // 黑色鲸鱼：居中，高度约占 72%（原生图标内容占比）
    let whaleSize = s * 0.72
    let whaleRect = NSRect(
        x: (s - whaleSize) / 2,
        y: (s - whaleSize) / 2,
        width: whaleSize,
        height: whaleSize
    )
    svg.draw(in: whaleRect)

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
let menuImage = NSImage(size: NSSize(width: 36, height: 36))
menuImage.lockFocus()
svg.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
menuImage.unlockFocus()
guard let tiff = menuImage.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render menubar icon\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: menubarPng))
print("wrote \(menubarPng) (menubar template)")
