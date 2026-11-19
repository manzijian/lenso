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

echo "==> 生成 Xcode 项目 (XcodeGen)"
xcodegen generate

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

# ── 小组件扩展签名 ────────────────────────────────────────────────
# 顺序必须是：先签 .appex，再回签 .app，让 App 的外层封条把扩展的最新哈希算进去。
# 反过来会让 App 的签名立刻失效。
# ───────────────────────────────────────────────────────────────────
APPEX_PATH="$APP_PATH/Contents/PlugIns/LensoWidgets.appex"
if [ -d "$APPEX_PATH" ]; then
  echo
  echo "==> 签名小组件扩展"
  # 必须带上沙盒 entitlement：pkd 只注册带 App Sandbox 的扩展
  codesign --force --sign "LENSO Dev Signing" \
    --entitlements "LENSOWidgets/LensoWidgets.entitlements" \
    "$APPEX_PATH"
  codesign --force --sign "LENSO Dev Signing" "$APP_PATH"
  echo "  ✅ 已签名：$(basename "$APPEX_PATH")"
fi

# ── 部署到固定位置 ────────────────────────────────────────────────
# 为什么：macOS TCC 权限按「路径 + 签名哈希」识别，DerivedData 是临时目录，
# 每次可能变，系统会把它当新 App 反复弹授权。固定到 ~/Applications 就一次搞定。
# ───────────────────────────────────────────────────────────────────
DEPLOY_DIR="$HOME/Applications"
DEPLOY_PATH="$DEPLOY_DIR/lenso.app"

echo
echo "==> 部署到固定位置：$DEPLOY_PATH"
mkdir -p "$DEPLOY_DIR"

# 如果旧的已在运行，先退出
if pgrep -x lenso >/dev/null 2>&1; then
  echo "  检测到 lenso 正在运行，先退出..."
  osascript -e 'tell application "lenso" to quit' 2>/dev/null || true
  sleep 1
fi

# 用 rsync 替换，保留属性
pkill -f "LensoWidgets.appex/Contents/MacOS/LensoWidgets" 2>/dev/null || true
rsync -a --delete "$APP_PATH/" "$DEPLOY_PATH/"
echo "  ✅ 已部署"

# 把小组件扩展注册进插件数据库，让它出现在「编辑小组件」里
if [ -d "$DEPLOY_PATH/Contents/PlugIns/LensoWidgets.appex" ]; then
  pluginkit -a "$DEPLOY_PATH/Contents/PlugIns/LensoWidgets.appex" 2>/dev/null || true
  echo "  ✅ 小组件扩展已注册"
fi

echo
echo "==> 启动 lenso"
open "$DEPLOY_PATH"
echo "  ✅ 已启动，不会再弹授权（固定签名 + 固定路径）"
