#!/bin/bash
# 方案1 Desktop 布局对齐验证
# 用法: bash scripts/verify-desktop-layout.sh
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

# 1+2. 运行时断言：折叠侧栏宽度 ~90 + logo 行避让红绿灯（--probe-sidebar）
PROBE_LOG=$(mktemp)
"$BIN" --probe-sidebar > "$PROBE_LOG" 2>&1 &
PROBE_PID=$!
for i in $(seq 1 30); do
  grep -q "collapsed probe" "$PROBE_LOG" && break
  sleep 1
done
kill "$PROBE_PID" 2>/dev/null; wait "$PROBE_PID" 2>/dev/null

COLW=$(grep -oE '"cls":"pI_x6G_sidebarCol","w":[0-9]+' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+$')
if [ -n "$COLW" ] && [ "$COLW" -ge 88 ] && [ "$COLW" -le 92 ]; then
  check collapsed_sidebar_width_~90 1 "运行时实测折叠侧栏宽 $COLW px（目标 90，含 1px 边框）"
else
  if [ -n "$COLW" ]; then
    check collapsed_sidebar_width_~90 0 "运行时实测折叠侧栏宽 ${COLW:-?}px（非 90）"
  else
    check collapsed_sidebar_width_~90 0 "needs_manual: 无 GUI 环境无法建窗；请在桌面会话运行 $BIN --probe-sidebar 后查看折叠侧栏宽度"
  fi
fi

LOGO=$(grep -oE 'marginTop=[0-9]+px' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+')
if [ -n "$LOGO" ] && [ "$LOGO" -ge 24 ] && [ "$LOGO" -le 34 ]; then
  check controls_below_traffic_lights_no_overlap 1 "运行时实测 logo 行 margin-top=$LOGO px（红绿灯行高 28，不重叠）"
else
  if [ -n "$LOGO" ]; then
    check controls_below_traffic_lights_no_overlap 0 "运行时实测 logo 行 margin-top=${LOGO:-?}px（异常）"
  else
    check controls_below_traffic_lights_no_overlap 0 "needs_manual: 无 GUI 环境无法建窗；请观察展开态侧栏 logo 行是否在红绿灯下方"
  fi
fi
rm -f "$PROBE_LOG"

# 3. 红绿灯右侧 ~32 拖拽带
if grep -q 'dragStripWidth: CGFloat = 32' "$SRC/DesktopLayout.swift" \
   && grep -q 'performDrag' "$SRC/DesktopLayout.swift" \
   && grep -q 'standardWindowButton' "$SRC/DSHDesktopApp.swift"; then
  check drag_strip_~32_right_of_traffic_lights 1 "原生 DragStripView 32pt，红绿灯右侧动态定位（standardWindowButton；56 为 sidebarRailWidth 命名常量）"
else
  check drag_strip_~32_right_of_traffic_lights 0 "拖拽带实现缺失"
fi

# 4. 顶栏按钮可点击（拖拽带不覆盖主内容顶栏）
if grep -q 'x: rightEdge' "$SRC/DSHDesktopApp.swift"; then
  check header_buttons_clickable 0 "needs_manual: 拖拽带仅覆盖红绿灯右侧 32pt 窄条，不覆盖主内容顶栏；请点击主内容顶栏按钮（侧栏切换/模型选择等）确认可点"
else
  check header_buttons_clickable 0 "拖拽带定位缺失"
fi

# 5. Dock 图标边距（主体占比缩小）
if grep -q 's \* 0.08' "$ROOT/scripts/make-icon.swift" \
   && grep -q 's \* 0.60' "$ROOT/scripts/make-icon.swift"; then
  check dock_icon_margin 1 "白底 inset 8% + 鲸鱼 60%（主体占比缩小、留白加大）"
else
  check dock_icon_margin 0 "图标边距参数缺失"
fi

echo ""
echo "[SUMMARY] passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
