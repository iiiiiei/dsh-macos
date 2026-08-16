#!/bin/bash
# 构建 DSH Desktop macOS 应用（无完整 Xcode 环境）
#
# 本机 CLT 处于半更新状态（编译器 swiftlang-6.0.3.1.10 与 SDK 1.5 混装，
# 且 /Library/Developer/CommandLineTools/usr/include/swift/ 同时存在
# module.modulemap 与 bridging.modulemap 导致 SwiftBridging 重复定义）。
# 解决办法：用 Swift 的 -vfsoverlay 把多余的 module.modulemap 映射为空文件。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DSH Desktop"
APP="$ROOT/build/$APP_NAME.app"
BIN="$ROOT/.build/DSHDesktop"

# --- 工具链修复：生成 vfsoverlay -------------------------------------------
CLT_ROOT="$(xcode-select -p 2>/dev/null || echo /Library/Developer/CommandLineTools)"
FIX_DIR="$ROOT/.build/toolchain-fix"
mkdir -p "$FIX_DIR"
: > "$FIX_DIR/empty.modulemap"
cat > "$FIX_DIR/overlay.yaml" <<EOF
{
  "version": 0,
  "case-sensitive": "true",
  "roots": [
    {
      "type": "file",
      "name": "$CLT_ROOT/usr/include/swift/module.modulemap",
      "external-contents": "$FIX_DIR/empty.modulemap"
    }
  ]
}
EOF

export TMPDIR="$FIX_DIR/tmp"
export CLANG_MODULE_CACHE_PATH="$FIX_DIR/clang-modcache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH"

echo "==> [1/4] swiftc (release)"
rm -f "$BIN"
swiftc -O \
  -target arm64-apple-macosx13.0 \
  -vfsoverlay "$FIX_DIR/overlay.yaml" \
  "$ROOT"/Sources/DSHDesktop/*.swift \
  -o "$BIN"

echo "==> [2/4] assemble bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DSHDesktop"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> [3/4] generate icon (官方鲸鱼 logo)"
ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift -vfsoverlay "$FIX_DIR/overlay.yaml" "$ROOT/scripts/make-icon.swift" \
  "$ROOT/Resources/whale.svg" "$ICONSET" "$ROOT/.build/whale-icon.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# 菜单栏模板图标 + 官方 SVG（运行时可用）
cp "$ROOT/.build/whale-icon.png" "$APP/Contents/Resources/whale-icon.png"
cp "$ROOT/Resources/whale.svg" "$APP/Contents/Resources/whale.svg"
# Appearance Overlay 资源（zh-simplified 等）
mkdir -p "$APP/Contents/Resources/overlays"
cp "$ROOT"/Resources/overlays/*.js "$APP/Contents/Resources/overlays/"

echo "==> [4/5] build DSHLauncher (菜单栏常驻)"
LAUNCHER="$ROOT/build/DSH Launcher.app"
rm -rf "$LAUNCHER"
mkdir -p "$LAUNCHER/Contents/MacOS" "$LAUNCHER/Contents/Resources"
swiftc -O \
  -target arm64-apple-macosx13.0 \
  -vfsoverlay "$FIX_DIR/overlay.yaml" \
  "$ROOT/Sources/DSHLauncher/main.swift" \
  -o "$LAUNCHER/Contents/MacOS/DSHLauncher"
cp "$ROOT/Resources/Info-Launcher.plist" "$LAUNCHER/Contents/Info.plist"
cp "$ROOT/.build/whale-icon.png" "$LAUNCHER/Contents/Resources/whale-icon.png"
cp "$APP/Contents/Resources/AppIcon.icns" "$LAUNCHER/Contents/Resources/AppIcon.icns"

echo "==> [5/5] codesign (ad-hoc)"
codesign --force --deep -s - "$APP"
codesign --force --deep -s - "$LAUNCHER"

echo ""
echo "==> done:"
echo "    $APP"
echo "    $LAUNCHER"
echo "    运行: open \"$LAUNCHER\""
echo "    自测: \"$APP/Contents/MacOS/DSHDesktop\" --selftest"
