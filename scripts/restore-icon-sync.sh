#!/bin/bash
# 还原白底黑鲸图标（macOS 规范）→ 构建 → 提交推送 → 同步到 ~/Desktop/dsh-macos
# 在你的终端运行（Desktop 受 TCC 保护，脚本在本终端执行才能读写）
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> [1/5] 还原 make-icon.swift 为白底黑鲸（遵循 macOS 图标规范）"
python3 << 'PYEOF'
import pathlib
p = pathlib.Path('scripts/make-icon.swift')
new = '''// 生成 DSH Desktop 应用图标（官方鲸鱼 logo 版）
// 用法: swift make-icon.swift <whale.svg> <iconset目录> <菜单栏模板png输出>
import AppKit

guard CommandLine.arguments.count >= 4 else {
    FileHandle.standardError.write("usage: make-icon.swift <whale.svg> <iconset> <menubar.png>\\n".data(using: .utf8)!)
    exit(1)
}
let svgPath = CommandLine.arguments[1]
let outputDir = CommandLine.arguments[2]
let menubarPng = CommandLine.arguments[3]

guard let svg = NSImage(contentsOfFile: svgPath) else {
    FileHandle.standardError.write("cannot load \\(svgPath)\\n".data(using: .utf8)!)
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
        FileHandle.standardError.write("failed to render \\(spec.name)\\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: "\\(outputDir)/\\(spec.name)")
    try png.write(to: url)
    print("wrote \\(url.path) (\\(spec.size)x\\(spec.size))")
}

// 菜单栏模板图标：36x36 黑色鲸鱼（alpha 形状，模板渲染自动适配深浅色）
let menuRep = renderPixels(size: 36) { ctx, s in
    svg.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
}
menuRep.size = NSSize(width: 18, height: 18)
guard let png = menuRep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render menubar icon\\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: menubarPng))
print("wrote \\(menubarPng) (menubar template 36px/18pt)")
'''
p.write_text(new, encoding='utf-8')
print("OK   make-icon.swift 已还原为白底黑鲸")
PYEOF

echo "==> [2/5] 构建"
bash scripts/build.sh 2>&1 | grep -E '^==>|error|wrote' | tail -10
test -f "build/DSH Desktop.app/Contents/Resources/AppIcon.icns" && echo "OK   AppIcon.icns 已生成"

echo "==> [3/5] 提交 + 推送"
git add scripts/make-icon.swift
if git diff --cached --quiet; then
  echo "无待提交改动（图标未变）"
else
  git commit -m "$(cat <<'MSG'
fix(icon): 还原白底黑鲸应用图标（遵循 macOS 图标规范：圆角21%/留边4.5%/鲸鱼居中58%）
MSG
)"
  git push origin HEAD || echo "!! 推送失败，请手动: git push"
fi

echo "==> [4/5] 同步最新代码到 ~/Desktop/dsh-macos"
SRC="$(pwd)"
DST="$HOME/Desktop/dsh-macos"
if [ -d "$DST" ]; then
  # 排除构建产物与临时文件，保留 .git（让 Desktop 与 GitHub 完全一致）
  rsync -a --delete \
    --exclude='.build/' --exclude='build/' --exclude='.DS_Store' \
    --exclude='*.removed' \
    "$SRC/" "$DST/"
  echo "OK   $DST 已与最新代码同步"
  echo "    构建产物可用: bash \"$DST/scripts/build.sh\" 重新生成"
else
  echo "!! $DST 不存在，跳过同步"
fi

echo "==> [5/5] 完成"
git status -sb | head -1
echo "提示：覆盖安装 -> sudo ditto \"build/DSH Desktop.app\" \"/Applications/DSH Desktop.app\""
