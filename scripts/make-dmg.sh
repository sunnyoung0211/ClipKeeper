#!/bin/bash
# 打包 DMG 安装包：编译 Release 版 → 放进一个带「应用程序」快捷方式的磁盘映像。
# 用户打开 DMG 后，把 ClipKeeper 拖到「应用程序」就装好了。
#
# 用法（在项目根目录运行）：
#   ./scripts/make-dmg.sh
# 输出：
#   build/ClipKeeper-<版本号>.dmg      版本号自动从 Xcode 项目里读取
#
# 说明：
# - 编译出的是通用版本（同时支持 Apple 芯片和 Intel 芯片的 Mac）。
# - 安装包里的应用会重新使用"临时签名"（ad-hoc）。开发时用的 Apple Development 证书里
#   带有开发者的 Apple ID 邮箱，拿到安装包的人都能查看，所以对外分发时换成不含任何个人信息的临时签名。
# - 安装包没有经过 Apple 公证，别人第一次打开时需要在「系统设置 → 隐私与安全性」里
#   点「仍要打开」（DMG 里附带了说明）。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ClipKeeper"
DERIVED="build/DerivedData"

# 从 Xcode 项目里读取版本号（MARKETING_VERSION）
VERSION=$(xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *MARKETING_VERSION = /{print $2; exit}')
DMG="build/$APP_NAME-$VERSION.dmg"

echo "▶ 编译 $APP_NAME $VERSION（Release，通用版本）…"
# generic/platform=macOS 表示"任意 Mac"，会同时编译 arm64 和 x86_64 两种架构
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" -quiet build
APP="$DERIVED/Build/Products/Release/$APP_NAME.app"

echo "▶ 准备磁盘映像里的内容…"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT   # 脚本结束时自动删除临时文件夹
cp -R "$APP" "$STAGING/"

echo "▶ 改用临时签名（不包含开发者的个人信息）…"
# 注意：必须先把原来的签名彻底删掉，再签临时签名。
# 如果直接用 --force 覆盖，新签名会沿用旧签名占的空间，旧证书的内容（包括邮箱）会残留在可执行文件里。
codesign --remove-signature "$STAGING/$APP_NAME.app/Contents/MacOS/$APP_NAME"
codesign --remove-signature "$STAGING/$APP_NAME.app"
# 去掉调试符号：编译时会把每个中间文件的完整路径（例如 /Users/你的用户名/...）记在可执行文件里，
# 这些信息对用户没用，还会暴露你的用户名
strip -S -x "$STAGING/$APP_NAME.app/Contents/MacOS/$APP_NAME"
codesign --sign - "$STAGING/$APP_NAME.app"
codesign --verify --strict "$STAGING/$APP_NAME.app"

echo "▶ 检查应用里是否还有个人信息…"
# 签名里不能有开发者证书和团队信息；整个应用里不能出现证书名、你的用户名或本机路径
if codesign -dvv "$STAGING/$APP_NAME.app" 2>&1 | grep -qE "^(Authority|TeamIdentifier=[^n])" \
   || grep -rqa -e "Apple Development" -e "$(whoami)" -e "/Users/" "$STAGING/$APP_NAME.app"; then
  echo "❌ 应用里仍然带有个人信息，已停止打包。可以用下面的命令查看是哪个文件："
  echo "   grep -rla -e \"Apple Development\" -e \"$(whoami)\" -e \"/Users/\" \"$STAGING/$APP_NAME.app\""
  trap - EXIT   # 保留临时文件夹，方便排查
  exit 1
fi
ln -s /Applications "$STAGING/应用程序"   # 「应用程序」文件夹的快捷方式，方便拖拽安装
cat > "$STAGING/安装说明.txt" <<'EOF'
ClipKeeper 安装说明
==================

1. 把 ClipKeeper 拖到旁边的「应用程序」文件夹。

2. 打开「应用程序」里的 ClipKeeper。
   第一次打开时，系统可能会提示"无法验证开发者"或"Apple 无法检查其是否包含恶意软件"，
   这是因为这个应用还没有经过 Apple 公证。请点「完成」关掉提示，然后：

   打开「系统设置 → 隐私与安全性」，滚动到最下面的「安全性」部分，
   找到"已阻止使用 ClipKeeper"，点旁边的「仍要打开」，输入电脑密码确认即可。
   之后再打开就不会提示了。

   （熟悉终端的话，也可以运行下面这条命令代替上面的操作：
     xattr -dr com.apple.quarantine /Applications/ClipKeeper.app ）

3. ClipKeeper 只在屏幕右上角的菜单栏显示一个回形针图标，不会出现在程序坞里。
   按 ⇧⌘V 打开剪贴板历史。

4. 第一次使用"自动粘贴"时，请按提示在
   「系统设置 → 隐私与安全性 → 辅助功能」里打开 ClipKeeper。
   以后升级到新版本时，如果自动粘贴不起作用了，请在辅助功能列表里选中 ClipKeeper，
   点「−」删掉，再重新打开 ClipKeeper 授权一次。

系统要求：macOS 14 或更高版本，支持 Apple 芯片和 Intel 芯片的 Mac。
EOF

echo "▶ 生成 $DMG …"
mkdir -p build
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" -quiet
hdiutil verify "$DMG" -quiet

echo "✅ 已生成 $DMG（$(du -h "$DMG" | cut -f1 | xargs)）"
echo "   SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
