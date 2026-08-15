#!/bin/bash
# DSH 官方 i18n 遗漏汉化补丁（修改 npx 缓存中的 client 插件产物）
# 注意：DSH 升级或 npx 缓存清理后需重新执行；服务器重启后生效。
set -euo pipefail

NPX_DIRS=(/Users/iiiiiei/.npm/_npx/*/)
PATCHED=0

for dir in "${NPX_DIRS[@]}"; do
  # 1) Session log 按钮：硬编码英文 -> 会话日志
  F1="${dir}node_modules/@deepseek-ai/dsh-session-log-export/lib/client.js"
  if [ -f "$F1" ] && grep -q '"Session log"' "$F1"; then
    sed -i '' 's/children: "Session log"/children: "会话日志"/' "$F1"
    echo "已汉化: $F1 (Session log -> 会话日志)"
    PATCHED=1
  fi

  # 2) 权限预设显示：Full access -> 完全访问
  F2="${dir}node_modules/@deepseek-ai/dsh-client-ui-permission-presets/lib/client.js"
  if [ -f "$F2" ] && grep -q '"Full access"' "$F2"; then
    sed -i '' 's/value === "danger-full-access" ? "Full access" : displayPresetName(name)/value === "danger-full-access" ? "完全访问" : displayPresetName(name)/' "$F2"
    sed -i '' 's/"启用 Full access"/"启用完全访问"/g; s/"确认启用 Full access？"/"确认启用完全访问？"/g; s/"确认启用 Full access？"/"确认启用完全访问？"/g' "$F2"
    echo "已汉化: $F2 (Full access -> 完全访问)"
    PATCHED=1
  fi
done

if [ "$PATCHED" -eq 0 ]; then
  echo "未找到需要汉化的文件（可能已补丁或包已更新）"
  exit 1
fi
echo "汉化补丁完成，重启 DSH 服务器后生效。"
