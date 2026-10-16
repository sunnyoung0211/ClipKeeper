#!/bin/bash
# 用命令行编译 Release 版本，生成 build/ClipKeeper.app
#
# 用法：
#   ./scripts/build.sh            只编译
#   ./scripts/build.sh --run      编译后立即运行
#   ./scripts/build.sh --install  编译后安装到 /Applications（日常使用推荐）
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ClipKeeper"
DERIVED="build/DerivedData"
PRODUCT="$DERIVED/Build/Products/Release/$APP_NAME.app"

echo "▶ 正在编译…"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$DERIVED" -quiet build

rm -rf "build/$APP_NAME.app"
cp -R "$PRODUCT" "build/$APP_NAME.app"
echo "✅ 已生成 build/$APP_NAME.app"

case "${1:-}" in
  --run)
    pkill -x "$APP_NAME" || true
    open "build/$APP_NAME.app"
    ;;
  --install)
    pkill -x "$APP_NAME" || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "build/$APP_NAME.app" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "✅ 已安装到 /Applications 并启动"
    ;;
esac
