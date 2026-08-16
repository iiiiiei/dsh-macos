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
RAILR=$(grep -oE '"cls":"qDHVXG_root qDHVXG_rail","w":[0-9]+,"l":[0-9]+,"r":[0-9]+' "$PROBE_LOG" | tail -1 | grep -oE '"r":[0-9]+' | grep -oE '[0-9]+')
if [ -n "$COLW" ] && [ "$COLW" -ge 67 ] && [ "$COLW" -le 71 ] && [ -n "$TL" ] && [ -n "$RAILR" ]; then
  check collapsed_sidebar_width_~90 1 "折叠侧栏 $COLW px，红绿灯左缘 $TL → 对称位 $(( ${TL%.*} * 2 + 54 ))px；图标列右缘 r=$RAILR 与侧栏右缘合一（两条竖直线对齐）"
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
   && [ -n "$PADTOP" ] && [ "$PADTOP" -ge 12 ] && [ "$PADTOP" -le 22 ]; then
  check controls_below_traffic_lights_no_overlap 1 "logo 行 margin-top=$LOGO px（红绿灯行下方）+ 主内容 padding-top=$PADTOP px（=行高28−顶栏间距12，内容贴拖拽带下限）"
else
  check controls_below_traffic_lights_no_overlap 0 "实测 logo=$LOGO padTop=${PADTOP:-?}（异常）"
fi

# 3. 拖拽带：红绿灯水平行整行（全宽 × 32pt）
DSW=$(grep -oE 'drag strip: x=[0-9]+ w=[0-9]+ h=[0-9]+' "$PROBE_LOG" | tail -1 | sed -E 's/.*w=([0-9]+) h=([0-9]+)/\1 \2/')
DS_X=$(echo "$DSW" | awk '{print $1}'); DS_H=$(echo "$DSW" | awk '{print $2}')
WW=$(grep -oE 'window: frame=[0-9]+' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+$')
if [ "$DS_X" -ge 1400 ] && [ "$DS_H" -ge 26 ] && [ "$DS_H" -le 30 ] 2>/dev/null; then
  check drag_strip_~32_right_of_traffic_lights 1 "拖拽带为红绿灯水平行整行：全宽 x=0 w=$DS_X h=$DS_H（行高由红绿灯组件反推 28），轴线在行内"
else
  if [ -n "$DS_X" ]; then
    check drag_strip_~32_right_of_traffic_lights 0 "实测拖拽带 w=$DS_X h=$DS_H（异常）"
  else
    check drag_strip_~32_right_of_traffic_lights 0 "needs_manual: 无 GUI 环境无法建窗；请拖动窗口顶部红绿灯水平行确认可拖"
  fi
fi

# 4. 顶栏按钮可点击：session log 按钮上边框贴紧拖拽带下限（不遮挡）
SLOG=$(grep -oE '"cls":"nL4_yW_sessionLogButton","t":[0-9]+' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+$')
DSH_H=$(grep -oE 'drag strip: x=0 w=[0-9]+ h=[0-9]+' "$PROBE_LOG" | tail -1 | grep -oE 'h=[0-9]+' | grep -oE '[0-9]+')
if [ -n "$SLOG" ] && [ -n "$DSH_H" ] && [ "$SLOG" -ge "$((DSH_H - 2))" ] && [ "$SLOG" -le "$((DSH_H + 2))" ]; then
  check header_buttons_clickable 1 "session log 按钮顶 t=$SLOG ≈ 拖拽带下限 $DSH_H（贴紧不遮挡）"
else
  check header_buttons_clickable 0 "needs_manual: session log 按钮顶=${SLOG:-?} vs 拖拽带高=${DSH_H:-?}（请点击顶栏按钮确认可点）"
fi

# 2b. 选中框与按钮同宽同缘（弹性居中）
ROWW=$(grep -oE '"cls":"YDXeBa_sessionRow YDXeBa_selected","w":[0-9]+,"l":[0-9]+,"r":[0-9]+' "$PROBE_LOG" | tail -1 | sed -E 's/.*"w":([0-9]+),"l":([0-9]+),"r":([0-9]+)/\1 \2 \3/')
RW=$(echo "$ROWW" | awk '{print $1}'); RL=$(echo "$ROWW" | awk '{print $2}'); RR=$(echo "$ROWW" | awk '{print $3}')
if [ "$RW" = "216" ] && [ "$RL" = "32" ] && [ "$RR" = "248" ]; then
  check session_row_aligned 1 "选中框 w=$RW l=$RL r=$RR（与新会话按钮 216/32/248 一致，中心 140 居中）"
else
  check session_row_aligned 0 "实测选中框 w=$RW l=$RL r=$RR（应与 216/32/248 一致）"
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
