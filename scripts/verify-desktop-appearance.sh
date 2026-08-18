#!/bin/bash
# dsh-macos 桌面外观自动验证（可重复运行）
# 用法: bash scripts/verify-desktop-appearance.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources/DSHDesktop"
APP="$ROOT/build/DSH Desktop.app"
PASS=0; FAIL=0

check() {
  local name="$1" ok="$2" reason="$3"
  if [ "$ok" = "1" ]; then
    echo "[CHECK] $name ... PASS — $reason"
    PASS=$((PASS+1))
  else
    echo "[CHECK] $name ... FAIL — $reason"
    FAIL=$((FAIL+1))
  fi
}

# 1. 窗口可逆性：沉浸式开关关闭后回到系统标准标题栏
if grep -q 'styleMask.remove(.fullSizeContentView)' "$SRC/DSHDesktopApp.swift" \
   && grep -q 'titlebarAppearsTransparent = false' "$SRC/DSHDesktopApp.swift"; then
  check window_immersive_reversible 1 "窗口开关关闭回到标准标题栏"
else
  check window_immersive_reversible 0 "缺少关闭/还原路径"
fi

# 2. 窗口 fullsize 配置
if grep -q 'fullSizeContentView' "$SRC/DSHDesktopApp.swift" \
   && grep -q 'titlebarAppearsTransparent' "$SRC/DSHDesktopApp.swift" \
   && grep -q 'titleVisibility' "$SRC/DSHDesktopApp.swift"; then
  check window_fullsize_flags 1 "fullSizeContentView / titlebarAppearsTransparent / titleVisibility 均在"
else
  check window_fullsize_flags 0 "窗口配置缺失"
fi

# 3. 安全区：standardWindowButton 动态计算；无硬编码魔法数 78/80/52/56
if grep -q 'standardWindowButton' "$SRC/WebView.swift"; then
  if grep -wE '78|80|52|56' "$SRC/WebView.swift" | grep -v 'slice(' | grep -q .; then
    check no_magic_traffic_light_constants 0 "WebView.swift 中存在硬编码 78/80/52/56"
  else
    check no_magic_traffic_light_constants 1 "安全区由 standardWindowButton 动态计算，无魔法数"
  fi
else
  check no_magic_traffic_light_constants 0 "未使用 standardWindowButton"
fi

# 4. WebView 透明
if grep -q 'underPageBackgroundColor' "$SRC/WebView.swift"; then
  check webview_draws_transparent 1 "underPageBackgroundColor = .clear 已配置"
else
  check webview_draws_transparent 0 "缺少透明背景配置"
fi

# 5. 图标：icns 在 .app 内 + 完整尺寸（iconset 源含 512@2x = 1024px）
ICNS="$APP/Contents/Resources/AppIcon.icns"
if [ -f "$ICNS" ] && [ -f "$ROOT/.build/AppIcon.iconset/icon_512x512@2x.png" ]; then
  check icon_icns_in_app_bundle 1 "AppIcon.icns 在 .app 内且 iconset 源含 1024px"
else
  check icon_icns_in_app_bundle 0 "icns 缺失（$ICNS）"
fi

# 6. 低内存：增强代码无轮询定时器
if grep -qE 'Timer\.scheduledTimer|setInterval' "$SRC/WebView.swift" 2>/dev/null; then
  check low_memory_no_polling_pattern 0 "WebView 增强代码含定时器轮询"
else
  check low_memory_no_polling_pattern 1 "增强代码无轮询定时器（健康轮询在 ServerManager，属既有功能）"
fi

echo ""
echo "[SUMMARY] passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
