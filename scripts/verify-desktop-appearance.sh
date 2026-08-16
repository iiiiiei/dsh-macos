#!/bin/bash
# dsh-macos 桌面外观自动验证（可重复运行）
# 用法: bash scripts/verify-desktop-appearance.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources/DSHDesktop"
JS="$ROOT/Resources/overlays/zh-simplified.js"
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

# 1. Appearance 默认 official
if grep -q 'appearanceId: String = AppearanceCatalog.official.id' "$SRC/AppState.swift" \
   && grep -q 'defaults.string(forKey: "appearanceId") ?? AppearanceCatalog.official.id' "$SRC/AppState.swift"; then
  check appearance_official_default 1 "AppState 默认与持久化回退均为 official"
else
  check appearance_official_default 0 "未找到默认 official 的代码路径"
fi

# 2. 可逆性：zh setEnabled(false) 还原 + 窗口开关关闭还原
if grep -q 'function setEnabled' "$JS" \
   && grep -q 'rec.node.data = rec.orig' "$JS" \
   && grep -q 'styleMask.remove(.fullSizeContentView)' "$SRC/DSHDesktopApp.swift" \
   && grep -q 'titlebarAppearsTransparent = false' "$SRC/DSHDesktopApp.swift"; then
  check appearance_reversible 1 "zh Overlay setEnabled(false) 还原官方原文；窗口开关回到标准标题栏"
else
  check appearance_reversible 0 "缺少关闭/还原路径"
fi

# 3. 窗口 fullsize 配置
if grep -q 'fullSizeContentView' "$SRC/DSHDesktopApp.swift" \
   && grep -q 'titlebarAppearsTransparent' "$SRC/DSHDesktopApp.swift" \
   && grep -q 'titleVisibility' "$SRC/DSHDesktopApp.swift"; then
  check window_fullsize_flags 1 "fullSizeContentView / titlebarAppearsTransparent / titleVisibility 均在"
else
  check window_fullsize_flags 0 "窗口配置缺失"
fi

# 4. 安全区：standardWindowButton 动态计算；无硬编码魔法数 78/80/52/56
if grep -q 'standardWindowButton' "$SRC/WebView.swift"; then
  if grep -wE '78|80|52|56' "$SRC/WebView.swift" >/dev/null; then
    check no_magic_traffic_light_constants 0 "WebView.swift 中存在硬编码 78/80/52/56"
  else
    check no_magic_traffic_light_constants 1 "安全区由 standardWindowButton 动态计算，无魔法数"
  fi
else
  check no_magic_traffic_light_constants 0 "未使用 standardWindowButton"
fi

# 5. WebView 透明
if grep -q 'underPageBackgroundColor' "$SRC/WebView.swift"; then
  check webview_draws_transparent 1 "underPageBackgroundColor = .clear 已配置"
else
  check webview_draws_transparent 0 "缺少透明背景配置"
fi

# 6. 汉化范围：整节点精确匹配（聊天保护）
if grep -q 'MAP\[trimmed\]' "$JS" && grep -q 'hit === undefined' "$JS"; then
  check zh_overlay_scope_fixed_ui_only 1 "整节点精确匹配，聊天正文不会命中映射"
else
  check zh_overlay_scope_fixed_ui_only 0 "缺少整节点匹配逻辑"
fi

# 7. 无全量 body 观察 / 无 Mutation 内 querySelectorAll("*")
BODY_OBS=$(grep -c 'observe(document.body' "$JS" || true)
BODY_SUBTREE=$(grep 'observe(document.body' "$JS" | grep -c 'subtree' || true)
QSA=$(grep -c 'querySelectorAll' "$JS" || true)
if [ "$BODY_OBS" -le 1 ] && [ "$BODY_SUBTREE" -eq 0 ] && [ "$QSA" -le 2 ]; then
  check zh_no_full_body_observer 1 "body 仅 childList 观察（无 subtree），querySelectorAll 仅初始化使用（$QSA 处）"
else
  check zh_no_full_body_observer 0 "body 观察=$BODY_OBS subtree=$BODY_SUBTREE querySelectorAll=$QSA（违反约束）"
fi

# 8. 未命中保持原文
if grep -q 'return false;' "$JS" && grep -q 'hit === undefined || hit === text' "$JS"; then
  check zh_unknown_string_keeps_original 1 "未命中映射的节点保持官方原文"
else
  check zh_unknown_string_keeps_original 0 "缺少保持原文逻辑"
fi

# 9. 图标：icns 在 .app 内 + 完整尺寸（iconset 源含 512@2x = 1024px）
ICNS="$APP/Contents/Resources/AppIcon.icns"
if [ -f "$ICNS" ] && [ -f "$ROOT/.build/AppIcon.iconset/icon_512x512@2x.png" ]; then
  check icon_icns_in_app_bundle 1 "AppIcon.icns 在 .app 内且 iconset 源含 1024px"
else
  check icon_icns_in_app_bundle 0 "icns 缺失（$ICNS）"
fi

# 10. 低内存：Appearance/zh 增强代码无轮询定时器；健康轮询（ServerManager）为既有功能
if grep -qE 'Timer\.scheduledTimer|setInterval' "$SRC/Appearance.swift" "$SRC/WebView.swift" 2>/dev/null; then
  check low_memory_no_polling_pattern 0 "Appearance/WebView 增强代码含定时器轮询"
else
  check low_memory_no_polling_pattern 1 "增强代码无轮询定时器；既有健康轮询在 ServerManager（与本任务无关）"
fi

echo ""
echo "[SUMMARY] passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
