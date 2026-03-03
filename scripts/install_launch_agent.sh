#!/usr/bin/env bash
set -euo pipefail

# 安装开机自启：
# 生成 LaunchAgents plist，并通过 launchctl 加载当前用户级自启动配置。
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_APP_PATH="$ROOT_DIR/dist/CursorTrailBar.app"
APP_PATH="${1:-$DEFAULT_APP_PATH}"
LABEL="com.lihan.cursortrailbar.autostart"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ ! -d "$APP_PATH" ]]; then
  echo "❌ 未找到 app: $APP_PATH"
  echo "请先执行: ./scripts/build_app.sh"
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$APP_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

echo "✅ 已安装开机自启: $PLIST_PATH"
