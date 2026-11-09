#!/bin/bash
# LENSO 开发构建（固定签名）
#
# 为什么不能直接用 `xcodebuild build`：
#   项目没有 DEVELOPMENT_TEAM，Xcode 会强制用 ad-hoc 签名（"Sign to Run Locally"），
#   而且命令行传 CODE_SIGN_IDENTITY 也会被覆盖回 "-"。
#   ad-hoc 签名的指定要求（designated requirement）是 cdhash，每次编译都会变，
#   macOS 就把它当成另一个 App —— 屏幕录制授权每次重建都要重新给。
#
# 这个脚本：先正常编译，再用固定自签证书重新签名。
#   证书的指定要求是「证书指纹」，只要证书不变，授权就一直在。
#
# 用法：
#   bash scripts/build.sh

set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> 编译"
xcodebuild -project LENSO.xcodeproj -scheme LENSO -configuration Debug build \
  | tail -3

APP_PATH="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/LENSO-*/Build/Products/Debug/*.app 2>/dev/null | head -1 || true)"
if [ -z "$APP_PATH" ]; then
  echo "找不到构建产物，编译可能失败了。" >&2
  exit 1
fi

echo
echo "==> 用固定身份重新签名"
bash scripts/setup-dev-signing.sh "$APP_PATH" | tail -12
