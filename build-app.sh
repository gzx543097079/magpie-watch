#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Magpie Watch"
APP_PATH="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="/Applications/magpie.app/Contents/Resources/magpie.icns"

cd "$ROOT"
swift build -c release

rm -rf "$APP_PATH"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/release/MagpieWatch" "$MACOS/MagpieWatch"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
mkdir -p "$RESOURCES/Wallpaper"
cp "$ROOT/design/dashboard.html" "$ROOT/design/dashboard.css" "$ROOT/design/dashboard.js" \
   "$ROOT/design/routing-stage.css" "$ROOT/design/routing-stage.js" "$ROOT/design/magpie-bird.svg" "$RESOURCES/Wallpaper/"

if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"
else
    echo "提示：未找到本机 Magpie 图标，应用将使用系统默认图标。"
fi

chmod +x "$MACOS/MagpieWatch"
plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "已生成：$APP_PATH"
