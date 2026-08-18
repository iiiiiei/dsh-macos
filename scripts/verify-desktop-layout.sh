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

# 参考外壳：macOS 折叠列宽 90px，红绿灯位置不参与 Web DOM 尺寸计算。
COLW=$(echo "$CP" | grep -oE '"cls":"pI_x6G_sidebarCol","w":[0-9]+' | grep -oE '[0-9]+$' | head -1)
if [ -n "$COLW" ] && [ "$COLW" -ge 88 ] && [ "$COLW" -le 92 ]; then
  check collapsed_sidebar_width_90 1 "折叠列宽 $COLW px（参考外壳 90px）"
else
  if [ -n "$COLW" ]; then
    check collapsed_sidebar_width_90 0 "运行时实测折叠侧栏宽 ${COLW:-?}px（异常）"
  else
    check collapsed_sidebar_width_90 0 "needs_manual: 无 GUI 环境无法建窗；请在桌面会话运行 $BIN --probe-sidebar 后查看折叠侧栏宽度"
  fi
fi

# 官方 56px 轨在 90px 侧栏内居中（轨 17..73，中心 45）
RAILL=$(echo "$CE" | grep -oE '"cls":"qDHVXG_root qDHVXG_rail","w":[0-9]+,"l":[0-9]+,"r":[0-9]+' | grep -oE '"l":[0-9]+' | grep -oE '[0-9]+' | head -1)
RAILR=$(echo "$CE" | grep -oE '"cls":"qDHVXG_root qDHVXG_rail","w":[0-9]+,"l":[0-9]+,"r":[0-9]+' | grep -oE '"r":[0-9]+' | grep -oE '[0-9]+' | head -1)
if [ -n "$RAILL" ] && [ "$RAILL" -ge 16 ] && [ "$RAILL" -le 18 ] && [ "$RAILR" -ge 72 ] && [ "$RAILR" -le 74 ]; then
  check rail_centered_in_sidebar 1 "官方 56px 轨居中（l=$RAILL r=$RAILR，中心 45），原生内边距保留"
else
  check rail_centered_in_sidebar 0 "实测轨 l=${RAILL:-?} r=${RAILR:-?}（应 17/73）"
fi

# 折叠轨内所有图标中心 x=45（对齐外壳列中心，图标原生 x 不动）
ICON_CENTERS=$(echo "$CE" | grep -oE '"center":[0-9]+' | grep -oE '[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ *$//')
ICON_COUNT=$(echo "$CE" | grep -oE '"center":[0-9]+' | wc -l | tr -d ' ')
if [ "$ICON_CENTERS" = "45" ] && [ "$ICON_COUNT" -ge 6 ]; then
  check collapsed_icons_centered_on_rail 1 "折叠轨内 $ICON_COUNT 个图标中心全部 x=45（外壳列中心）"
else
  check collapsed_icons_centered_on_rail 0 "图标中心集合=[${ICON_CENTERS:-无}]（应全部为 45，数量≥6，实测 $ICON_COUNT）"
fi

# 红绿灯：原生按钮尺寸/间距不改，只校准到 Codex/参考外壳中心锚点 16pt,16pt。
if grep -q 'traffic aligned:.*targetCenter=(23,24)' "$PROBE_LOG"; then
  check traffic_lights_codex_anchor 1 "原生红绿灯已对齐到中心锚点 (23,24)，按钮尺寸/间距由 AppKit 保留"
else
  check traffic_lights_codex_anchor 0 "未找到 traffic aligned 运行时断言（需要在桌面会话重新运行探针）"
fi

# 外壳覆盖层不得接管官方 Logo、会话行或 Hero 的尺寸。
if grep -q 'grid-template-columns: 90px' "$ROOT/Resources/overlays/desktop-layout.js" \
   && ! grep -qE 'YDXeBa_(project|session)Row|wSkVaW_root|--dsh-traffic-' "$ROOT/Resources/overlays/desktop-layout.js"; then
  check official_web_layout_untouched 1 "覆盖层只保留外壳列与折叠轨规则"
else
  check official_web_layout_untouched 0 "覆盖层仍包含官方功能节点尺寸规则"
fi

# 3. 拖拽带：参考外壳 32pt 高，左右预留系统按钮安全区。
DSW=$(grep -oE 'drag strip: x=[0-9]+ w=[0-9]+ h=[0-9]+' "$PROBE_LOG" | tail -1 | sed -E 's/.*x=([0-9]+) w=([0-9]+) h=([0-9]+)/\1 \2 \3/')
DS_X=$(echo "$DSW" | awk '{print $1}'); DS_W=$(echo "$DSW" | awk '{print $2}'); DS_H=$(echo "$DSW" | awk '{print $3}')
if [ "$DS_X" -ge 80 ] && [ "$DS_W" -gt 600 ] && [ "$DS_H" -ge 46 ] && [ "$DS_H" -le 50 ] 2>/dev/null; then
  check drag_strip_reference_row 1 "拖拽带 x=$DS_X w=$DS_W h=$DS_H（左侧安全区≥80，按 Codex 同屏测量校准行高48）"
else
  check drag_strip_reference_row 0 "needs_manual: 实测拖拽带 x=${DS_X:-?} w=${DS_W:-?} h=${DS_H:-?}（应为行高48）"
fi
if grep -qE "viewtree: .*DragStripView\{(8[0-9]|9[0-9]|[1-9][0-9]{2}),0," "$PROBE_LOG"; then
  check drag_strip_at_top 1 "拖拽带位于窗口顶部（参考外壳透明 caption row）"
else
  check drag_strip_at_top 0 "viewtree 未见顶部 DragStripView{0,0,..}（拖拽带位置异常）"
fi

# 4. 顶栏按钮安全区：原生 overlay 右侧预留空间，不抢 Session log 点击。
if grep -q 'topControlsSafeWidth' "$ROOT/Sources/DSHDesktop/DSHDesktopApp.swift"; then
  check header_buttons_safe_area 1 "拖拽带右侧预留顶部按钮安全区"
else
  check header_buttons_safe_area 0 "未发现顶部按钮安全区"
fi

# 会话/文件名栏由官方 Web UI 自己负责，覆盖层不再写内联宽度。
if ! grep -qE 'YDXeBa_(project|session)Row' "$ROOT/Resources/overlays/desktop-layout.js"; then
  check official_session_rows_untouched 1 "未接管官方会话/文件名行尺寸"
else
  check official_session_rows_untouched 0 "覆盖层仍接管官方会话/文件名行尺寸"
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
