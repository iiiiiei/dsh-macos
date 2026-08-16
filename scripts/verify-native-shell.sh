#!/bin/bash
# Native Shell 自动验证：窗口顶到顶 + 图标
# 用法: bash scripts/verify-native-shell.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources/DSHDesktop"
APP="$ROOT/build/DSH Desktop.app"
BIN="$APP/Contents/MacOS/DSHDesktop"
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

# 1. 窗口顶到顶运行时断言：运行应用，从日志读 contentView vs window frame
GEO_LOG=$(mktemp)
"$BIN" > "$GEO_LOG" 2>&1 &
APP_PID=$!
for i in $(seq 1 12); do
  grep -q "edgeToEdge=" "$GEO_LOG" && break
  sleep 1
done
kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null
EDGE=$(grep -oE "edgeToEdge=(true|false)" "$GEO_LOG" | tail -1)
if [ "$EDGE" = "edgeToEdge=true" ]; then
  check window_edge_to_edge_runtime 1 "实测 contentView 高度 == window 高度（$EDGE），内容覆盖到窗口顶边"
else
  if grep -q "edgeToEdge=" "$GEO_LOG"; then
    check window_edge_to_edge_runtime 0 "实测 $EDGE"
  else
    check window_edge_to_edge_runtime 0 "needs_manual: 无 GUI 环境无法建窗；请在桌面会话运行 $BIN 后观察红绿灯悬浮"
  fi
fi

# 2. 安全区动态计算（standardWindowButton），无魔法数
if grep -q 'standardWindowButton' "$SRC/WebView.swift"; then
  if grep -wE '78|80|52|56' "$SRC/WebView.swift" >/dev/null; then
    check traffic_light_dynamic_inset 0 "存在硬编码魔法数 78/80/52/56"
  else
    check traffic_light_dynamic_inset 1 "standardWindowButton 动态计算并注入 CSS 变量，无魔法数"
  fi
else
  check traffic_light_dynamic_inset 0 "未使用 standardWindowButton"
fi

# 3. 沉浸式标题栏不是用户开关（设置主路径无该开关）
if grep -q '沉浸式标题栏' "$SRC/SettingsView.swift"; then
  check no_user_facing_immersive_toggle 0 "设置页仍暴露沉浸式标题栏开关"
else
  check no_user_facing_immersive_toggle 1 "设置主路径无沉浸式标题栏开关（顶到顶为默认行为）"
fi

# 4. 图标：icns 在 .app 内、含 1024px、Info 声明正确
ICNS="$APP/Contents/Resources/AppIcon.icns"
if [ -f "$ICNS" ] && [ -f "$ROOT/.build/AppIcon.iconset/icon_512x512@2x.png" ] \
   && grep -q 'CFBundleIconFile' "$APP/Contents/Info.plist" \
   && grep -q 'AppIcon' "$APP/Contents/Info.plist"; then
  check appicon_in_bundle 1 "AppIcon.icns 在 .app 内（含 1024px），Info.plist 声明 CFBundleIconFile=AppIcon"
else
  check appicon_in_bundle 0 "icns 或 Info 声明缺失"
fi

rm -f "$GEO_LOG"
echo ""
echo "[SUMMARY] passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
