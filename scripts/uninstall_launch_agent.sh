#!/usr/bin/env bash
set -euo pipefail

# 卸载开机自启：
# 从 LaunchAgents 中移除 RainbowCursor 的用户级自启动配置。
LABEL="com.lihan.rainbowcursor.autostart"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ -f "$PLIST_PATH" ]]; then
  launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
  rm -f "$PLIST_PATH"
  echo "✅ 已移除开机自启: $PLIST_PATH"
else
  echo "ℹ️ 未发现开机自启配置: $PLIST_PATH"
fi
