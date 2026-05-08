#!/bin/bash
# Mac 端 .app 打包 + 启动脚本（v15.25 i18n 修复必备）
#
# 用途：把 swift build 的裸 executable 包装成完整 macOS .app（含 Info.plist + 资源 bundle）
# 让 macOS 系统菜单（File/Edit/Window/Help）按 CFBundleLocalizations 自动切语言
# 同时让 SwiftUI Text/Button 等字面量从打包好的 .lproj 读 catalog 翻译
#
# 用法：
#   ./run-mac.sh              # debug build + 启动
#   ./run-mac.sh release      # release build + 启动
#   ./run-mac.sh debug build  # 只 build，不启动

set -e

cd "$(dirname "$0")"

CONFIG=${1:-debug}
ACTION=${2:-run}
APP_NAME=MainApp

echo "→ swift build --product $APP_NAME -c $CONFIG"
swift build --product "$APP_NAME" -c "$CONFIG"

BIN_PATH=$(swift build --show-bin-path -c "$CONFIG")
BINARY="$BIN_PATH/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "✗ 找不到 binary: $BINARY"
    exit 1
fi

APP_BUNDLE="$BIN_PATH/$APP_NAME.app"
echo "→ 打包 .app: $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 拷贝 SPM 自动生成的所有 *.bundle（含 catalog 编译产物 .lproj/Localizable.strings）
shopt -s nullglob
for spm_bundle in "$BIN_PATH"/*.bundle; do
    if [ -d "$spm_bundle/Contents/Resources" ]; then
        cp -R "$spm_bundle/Contents/Resources/"* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
    else
        cp -R "$spm_bundle/"* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
    fi
done
shopt -u nullglob

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MainApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.futuresterminal.macos</string>
    <key>CFBundleName</key>
    <string>FuturesTerminal</string>
    <key>CFBundleDisplayName</key>
    <string>期货终端</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>15.25</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>en</string>
    </array>
</dict>
</plist>
PLIST

echo "✓ .app 已就绪"
echo "  路径：$APP_BUNDLE"
echo "  支持语言：zh-Hans / en（系统语言切换自动跟随）"

if [ "$ACTION" != "build" ]; then
    echo "→ 启动 $APP_BUNDLE"
    open "$APP_BUNDLE"
fi
