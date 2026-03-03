#!/usr/bin/env bash
set -euo pipefail

# 打包脚本：
# 1) 以 release 模式构建可执行文件；
# 2) 组装 .app 目录结构与 Info.plist；
# 3) 尝试进行 ad-hoc 签名（失败时不阻断）。
APP_NAME="CursorTrailBar"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/${APP_NAME}"
APP_ICON_PATH="$ROOT_DIR/assets/AppIcon.icns"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
if [ -f "$APP_ICON_PATH" ]; then
  cp "$APP_ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>CursorTrailBar</string>
    <key>CFBundleExecutable</key>
    <string>CursorTrailBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.lihan.cursortrailbar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>CursorTrailBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "✅ App 已生成: $APP_DIR"
