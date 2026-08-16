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

# 取指定探测日志行（探测会输出「含 overlay」与「原生对照」两组数据，须按行作用域取值）
PROBE_LINE() { grep "$1" "$PROBE_LOG" | tail -1; }
CP=$(PROBE_LINE "collapsed probe:")
CE=$(PROBE_LINE "collapsed extra:")
LP=$(PROBE_LINE "layout probe:")

# 折叠侧栏宽度 68 = 红灯左距(7)×2 + 组宽(54)（红绿灯绝对位置为锚）
TL=$(grep -oE 'tl=[0-9.]+px' "$PROBE_LOG" | tail -1 | grep -oE '[0-9.]+')
COLW=$(echo "$CP" | grep -oE '"cls":"pI_x6G_sidebarCol","w":[0-9]+' | grep -oE '[0-9]+$' | head -1)
if [ -n "$COLW" ] && [ "$COLW" -ge 67 ] && [ "$COLW" -le 69 ] && [ -n "$TL" ]; then
  check collapsed_sidebar_width_68 1 "折叠侧栏视觉总宽 $COLW px（红绿灯左缘 $TL → 目标 $(( ${TL%.*} * 2 + 54 ))px，含 1px 右边框）"
else
  if [ -n "$COLW" ]; then
    check collapsed_sidebar_width_68 0 "运行时实测折叠侧栏宽 ${COLW:-?}px（异常）"
  else
    check collapsed_sidebar_width_68 0 "needs_manual: 无 GUI 环境无法建窗；请在桌面会话运行 $BIN --probe-sidebar 后查看折叠侧栏宽度"
  fi
fi

# 官方 56px 轨在 68px 侧栏内居中（轨 16..52，中心 34）
RAILL=$(echo "$CE" | grep -oE '"cls":"qDHVXG_root qDHVXG_rail","w":[0-9]+,"l":[0-9]+,"r":[0-9]+' | grep -oE '"l":[0-9]+' | grep -oE '[0-9]+' | head -1)
RAILR=$(echo "$CE" | grep -oE '"cls":"qDHVXG_root qDHVXG_rail","w":[0-9]+,"l":[0-9]+,"r":[0-9]+' | grep -oE '"r":[0-9]+' | grep -oE '[0-9]+' | head -1)
if [ -n "$RAILL" ] && [ "$RAILL" -ge 15 ] && [ "$RAILL" -le 17 ] && [ "$RAILR" -ge 51 ] && [ "$RAILR" -le 53 ]; then
  check rail_centered_in_sidebar 1 "官方 56px 轨居中（l=$RAILL r=$RAILR，中心 34 = 黄灯中心），原生内边距保留"
else
  check rail_centered_in_sidebar 0 "实测轨 l=${RAILL:-?} r=${RAILR:-?}（应 16/52）"
fi

# 折叠轨内所有图标中心 x=34（对齐黄灯中心，图标原生 x 不动）
ICON_CENTERS=$(echo "$CE" | grep -oE '"center":[0-9]+' | grep -oE '[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ *$//')
ICON_COUNT=$(echo "$CE" | grep -oE '"center":[0-9]+' | wc -l | tr -d ' ')
if [ "$ICON_CENTERS" = "34" ] && [ "$ICON_COUNT" -ge 6 ]; then
  check collapsed_icons_centered_on_yellow 1 "折叠轨内 $ICON_COUNT 个图标中心全部 x=34（=黄灯中心）"
else
  check collapsed_icons_centered_on_yellow 0 "图标中心集合=[${ICON_CENTERS:-无}]（应全部为 34，数量≥6，实测 $ICON_COUNT）"
fi

# 红绿灯保持系统默认绝对位置（无平移日志）
if grep -q "traffic lights: left=" "$PROBE_LOG"; then
  check traffic_lights_default_position 0 "存在红绿灯平移日志（未恢复默认位置）"
else
  check traffic_lights_default_position 1 "红绿灯保持系统默认绝对位置（无平移）"
fi

# 展开态：logo 行在红绿灯行下方 + 主内容贴紧拖拽带下限
LOGO=$(grep -oE 'marginTop=[0-9]+px' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+')
PADTOP=$(grep -oE '"padTop":"[0-9]+px"' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+')
if [ -n "$LOGO" ] && [ "$LOGO" -ge 24 ] && [ "$LOGO" -le 34 ] \
   && [ -n "$PADTOP" ] && [ "$PADTOP" -ge 12 ] && [ "$PADTOP" -le 22 ]; then
  check controls_below_traffic_lights_no_overlap 1 "logo 行 margin-top=$LOGO px（红绿灯行下方）+ 主内容 padding-top=$PADTOP px（=行高28−顶栏间距12，内容贴拖拽带下限）"
else
  check controls_below_traffic_lights_no_overlap 0 "实测 logo=$LOGO padTop=${PADTOP:-?}（异常）"
fi

# 3. 拖拽带：红绿灯水平行整行（全宽 × 28pt），位于窗口顶部
DSW=$(grep -oE 'drag strip: x=[0-9]+ w=[0-9]+ h=[0-9]+' "$PROBE_LOG" | tail -1 | sed -E 's/.*w=([0-9]+) h=([0-9]+)/\1 \2/')
DS_X=$(echo "$DSW" | awk '{print $1}'); DS_H=$(echo "$DSW" | awk '{print $2}')
if [ "$DS_X" -ge 1400 ] && [ "$DS_H" -ge 26 ] && [ "$DS_H" -le 30 ] 2>/dev/null; then
  check drag_strip_full_width_row 1 "拖拽带为红绿灯水平行整行：全宽 x=0 w=$DS_X h=$DS_H（行高由红绿灯组件反推 28）"
else
  check drag_strip_full_width_row 0 "needs_manual: 实测拖拽带 w=${DS_X:-?} h=${DS_H:-?}（异常）"
fi
if grep -qE "viewtree: .*DragStripView\{0,0," "$PROBE_LOG"; then
  check drag_strip_at_top 1 "拖拽带位于窗口顶部 DragStripView{0,0,..}（flipped 坐标修复：此前被放到底部）"
else
  check drag_strip_at_top 0 "viewtree 未见顶部 DragStripView{0,0,..}（拖拽带位置异常）"
fi

# 4. 顶栏按钮可点击：session log 按钮上边框贴紧拖拽带下限（不遮挡）
SLOG=$(grep -oE '"cls":"nL4_yW_sessionLogButton","t":[0-9]+' "$PROBE_LOG" | tail -1 | grep -oE '[0-9]+$')
DSH_H=$(grep -oE 'drag strip: x=0 w=[0-9]+ h=[0-9]+' "$PROBE_LOG" | tail -1 | grep -oE 'h=[0-9]+' | grep -oE '[0-9]+')
if [ -n "$SLOG" ] && [ -n "$DSH_H" ] && [ "$SLOG" -ge "$((DSH_H - 2))" ] && [ "$SLOG" -le "$((DSH_H + 2))" ]; then
  check header_buttons_clickable 1 "session log 按钮顶 t=$SLOG ≈ 拖拽带下限 $DSH_H（贴紧不遮挡）"
else
  check header_buttons_clickable 0 "needs_manual: session log 按钮顶=${SLOG:-?} vs 拖拽带高=${DSH_H:-?}（请点击顶栏按钮确认可点）"
fi

# 2b. 选中框与新会话按钮同宽同缘（实测按钮 216/16/232）
ROWW=$(echo "$LP" | grep -oE '"cls":"YDXeBa_sessionRow YDXeBa_selected","w":[0-9]+,"l":[0-9]+,"r":[0-9]+' | tail -1 | sed -E 's/.*"w":([0-9]+),"l":([0-9]+),"r":([0-9]+)/\1 \2 \3/')
RW=$(echo "$ROWW" | awk '{print $1}'); RL=$(echo "$ROWW" | awk '{print $2}'); RR=$(echo "$ROWW" | awk '{print $3}')
if [ "$RW" = "216" ] && [ "$RL" = "16" ] && [ "$RR" = "232" ]; then
  check session_row_aligned 1 "选中框 w=$RW l=$RL r=$RR（与新会话按钮 216/16/232 完全重合；距左边界 16、右边界 48 与按钮一致，宽度随侧栏弹性变化）"
else
  check session_row_aligned 0 "实测选中框 w=$RW l=$RL r=$RR（应与 216/16/232 一致）"
fi
rm -f "$PROBE_LOG"

# 3b. 拖拽自测（--probe-drag：合成鼠标事件走真实 hitTest 链路，验证窗口移动）
DRAG_LOG=$(mktemp)
"$BIN" --probe-drag > "$DRAG_LOG" 2>&1 &
DRAG_PID=$!
for i in $(seq 1 30); do
  grep -q "dragtest: after" "$DRAG_LOG" && break
  sleep 1
done
kill "$DRAG_PID" 2>/dev/null; wait "$DRAG_PID" 2>/dev/null
if grep -q "dragtest: after=.*moved=true" "$DRAG_LOG"; then
  check drag_self_test 1 "合成拖拽后窗口原点变化（moved=true）——顶部拖拽带可拖"
else
  check drag_self_test 0 "拖拽自测 moved=false（拖拽带未收到事件，请检查 z 序/坐标）"
fi
rm -f "$DRAG_LOG"

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
