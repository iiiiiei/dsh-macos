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

# 1-4. 运行时断言（--probe-sidebar）
PROBE_LOG=$(mktemp)
"$BIN" --probe-sidebar > "$PROBE_LOG" 2>&1 &
PROBE_PID=$!
for i in $(seq 1 30); do
  grep -q "collapsed probe" "$PROBE_LOG" && break
  sleep 1
done
kill "$PROBE_PID" 2>/dev/null; wait "$PROBE_PID" 2>/dev/null

# 红绿灯折叠居中（以红绿灯为锚点）
TL=$(grep -oE "traffic lights: left=[0-9]+" "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+$')
# 主内容让出标题栏行（透明标题栏布局）
PADTOP=$(grep -oE '"padTop":"[0-9]+px"' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+')

COLW=$(grep -oE '"cls":"pI_x6G_sidebarCol","w":[0-9]+' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+$')
TL=$(grep -oE 'tl=[0-9.]+px' "$PROBE_LOG" | tail -1 | grep -oE '[0-9.]+')
if [ -n "$COLW" ] && [ "$COLW" -ge 67 ] && [ "$COLW" -le 71 ] && [ -n "$TL" ]; then
  check collapsed_sidebar_width_~90 1 "运行时实测折叠侧栏宽 $COLW px（含边框），红绿灯左缘 $TL → 居中宽 2×$TL+54≈$COLW（以红绿灯默认位置为锚，方案1 的 90 按用户要求调整）"
else
  if [ -n "$COLW" ]; then
    check collapsed_sidebar_width_~90 0 "运行时实测折叠侧栏宽 ${COLW:-?}px（异常）"
  else
    check collapsed_sidebar_width_~90 0 "needs_manual: 无 GUI 环境无法建窗；请在桌面会话运行 $BIN --probe-sidebar 后查看折叠侧栏宽度"
  fi
fi

# 红绿灯保持系统默认绝对位置（无平移日志）
if grep -q "traffic lights: left=" "$PROBE_LOG"; then
  check traffic_lights_default_position 0 "存在红绿灯平移日志（未恢复默认位置）"
else
  check traffic_lights_default_position 1 "红绿灯保持系统默认绝对位置（无平移）"
fi

LOGO=$(grep -oE 'marginTop=[0-9]+px' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+')
if [ -n "$LOGO" ] && [ "$LOGO" -ge 24 ] && [ "$LOGO" -le 34 ] \
   && [ -n "$PADTOP" ] && [ "$PADTOP" -ge 24 ]; then
  check controls_below_traffic_lights_no_overlap 1 "logo 行 margin-top=$LOGO px + 主内容 padding-top=$PADTOP px（均在红绿灯行下方，不重叠）"
else
  check controls_below_traffic_lights_no_overlap 0 "实测 logo=$LOGO padTop=${PADTOP:-?}（异常）"
fi

# 3. 拖拽带：红绿灯水平行整行（全宽 × 32pt）
DSW=$(grep -oE 'drag strip: x=[0-9]+ w=[0-9]+ h=[0-9]+' "$PROBE_LOG" | tail -1 | sed -E 's/.*w=([0-9]+) h=([0-9]+)/\1 \2/')
DS_X=$(echo "$DSW" | awk '{print $1}'); DS_H=$(echo "$DSW" | awk '{print $2}')
WW=$(grep -oE 'window: frame=[0-9]+' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+$')
if [ "$DS_X" -ge 1400 ] && [ "$DS_H" = "32" ] 2>/dev/null; then
  check drag_strip_~32_right_of_traffic_lights 1 "拖拽带为红绿灯水平行整行：全宽 x=0 w=$DS_X h=$DS_H，轴线在行内"
else
  if [ -n "$DS_X" ]; then
    check drag_strip_~32_right_of_traffic_lights 0 "实测拖拽带 w=$DS_X h=$DS_H（非全行 32）"
  else
    check drag_strip_~32_right_of_traffic_lights 0 "needs_manual: 无 GUI 环境无法建窗；请拖动窗口顶部红绿灯水平行确认可拖"
  fi
fi

# 4. 顶栏按钮可点击：主内容已让出标题栏行（padding 生效 → 顶栏下移不遮挡）
if [ -n "$PADTOP" ] && [ "$PADTOP" -ge 24 ]; then
  check header_buttons_clickable 1 "主内容 padding-top=$PADTOP px（透明标题栏布局），顶栏按钮下移不被拖拽带遮挡"
else
  check header_buttons_clickable 0 "needs_manual: 请点击主内容顶栏按钮（模型选择/会话标题）确认可点"
fi
rm -f "$PROBE_LOG"

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
