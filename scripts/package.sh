#!/bin/bash
# LENSO 发布打包：构建 Release 版本，生成带版本号的 DMG / ZIP
#
# 用法：
#   bash scripts/package.sh <版本号> [build 号]
#   bash scripts/package.sh 1.0.0 42
#
# 版本号通过 xcodebuild 的 MARKETING_VERSION 覆盖，写入 App 的 Info.plist，
# 不依赖 project.yml 里的默认值；build 号对应 CFBundleVersion。
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
BUILD="${2:-1}"
if [ -z "$VERSION" ]; then
  echo "用法: bash scripts/package.sh <版本号，如 1.0.0> [build 号]" >&2
  exit 1
fi

DIST_DIR="$(pwd)/dist"
mkdir -p "$DIST_DIR"

DMG_PATH="$DIST_DIR/LENSO-$VERSION.dmg"
ZIP_PATH="$DIST_DIR/LENSO-$VERSION.zip"

echo "==> 生成 Xcode 项目 (XcodeGen)"
xcodegen generate

echo "==> 编译 Release（版本 $VERSION / build $BUILD）"
xcodebuild -project LENSO.xcodeproj -scheme LENSO -configuration Release build \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  | tail -3

APP_PATH="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/LENSO-*/Build/Products/Release/*.app 2>/dev/null | head -1 || true)"
if [ -z "$APP_PATH" ]; then
  echo "找不到 Release 构建产物，编译可能失败了。" >&2
  exit 1
fi

echo
echo "==> 用固定身份重新签名"
bash scripts/setup-dev-signing.sh "$APP_PATH" | tail -6

APPEX_PATH="$APP_PATH/Contents/PlugIns/LensoWidgets.appex"
if [ -d "$APPEX_PATH" ]; then
  echo
  echo "==> 签名小组件扩展"
  codesign --force --sign "LENSO Dev Signing" \
    --entitlements "LENSOWidgets/LensoWidgets.entitlements" \
    "$APPEX_PATH"
  codesign --force --sign "LENSO Dev Signing" "$APP_PATH"
fi

echo
echo "==> 校验产物版本"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
echo "  CFBundleShortVersionString = $APP_VERSION"
echo "  CFBundleVersion            = $APP_BUILD"
if [ "$APP_VERSION" != "$VERSION" ]; then
  echo "版本号不一致，打包中止。" >&2
  exit 1
fi

echo
echo "==> 清理旧产物"
rm -f "$DMG_PATH" "$ZIP_PATH"

STAGE_DIR="/tmp/lenso-dmg-staging-$$"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> 生成 DMG: dist/LENSO-$VERSION.dmg"
hdiutil create -volname "LENSO $VERSION" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "==> 生成 ZIP: dist/LENSO-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

rm -rf "$STAGE_DIR"

echo
echo "打包完成！"
ls -lh "$DMG_PATH" "$ZIP_PATH"
