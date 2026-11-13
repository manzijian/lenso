#!/bin/bash
# LENSO 打包脚本：生成可直接安装的 .dmg 磁盘映像与 .zip 压缩包
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> 确保最新构建并签名"
bash scripts/build.sh

APP_PATH="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/LENSO-*/Build/Products/Debug/*.app 2>/dev/null | head -1 || true)"
if [ -z "$APP_PATH" ]; then
  echo "找不到构建产物，请先检查编译。" >&2
  exit 1
fi

DIST_DIR="$(pwd)/dist"
mkdir -p "$DIST_DIR"

STAGE_DIR="/tmp/lenso-dmg-staging-$$"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

echo "==> 准备安装包内容"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> 生成 DMG 安装镜像: dist/lenso-preview.dmg"
rm -f "$DIST_DIR/lenso-preview.dmg"
hdiutil create -volname "LENSO Preview" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DIST_DIR/lenso-preview.dmg"

echo "==> 生成 ZIP 便携压缩包: dist/lenso-preview.zip"
rm -f "$DIST_DIR/lenso-preview.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/lenso-preview.zip"

rm -rf "$STAGE_DIR"

echo
echo "打包完成！产物位于："
ls -lh "$DIST_DIR"
