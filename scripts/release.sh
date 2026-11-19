#!/bin/bash
# LENSO 发布：同步版本号 → 打包 → 提交并打 tag → 创建 GitHub Release
#
# 版本规范（语义化版本）：
#   主版本.次版本.修订号  →  tag 为 v1.0.0
#   主版本：不兼容的大改版   次版本：向下兼容的新功能   修订号：修复
#
# CFBundleShortVersionString = 版本号，CFBundleVersion = 当前提交数（单调递增）
#
# 用法：
#   bash scripts/release.sh 1.0.0
#
# 前置条件：工作区干净、已在 main 分支、gh 已登录且有该仓库权限。
set -euo pipefail

cd "$(dirname "$0")/.."

REPO="manzijian/lenso"
VERSION="${1:-}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法: bash scripts/release.sh <主版本.次版本.修订号>，例如 1.0.0" >&2
  exit 1
fi

TAG="v$VERSION"
BRANCH="$(git branch --show-current)"

if [ "$BRANCH" != "main" ]; then
  echo "当前分支是 $BRANCH，请在 main 上发布。" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "工作区有未提交的改动，先提交或暂存后再发布：" >&2
  git status --short >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1 || git ls-remote --tags origin "refs/tags/$TAG" | grep -q .; then
  echo "标签 $TAG 已存在（本地或远端），换个版本号。" >&2
  exit 1
fi

BUILD="$(( $(git rev-list --count HEAD) + 1 ))"

echo "==> 版本 ${VERSION}（tag ${TAG}，build ${BUILD}）"
/usr/bin/sed -i '' -E "s/^    MARKETING_VERSION: .*/    MARKETING_VERSION: \"$VERSION\"/" project.yml
/usr/bin/sed -i '' -E "s/^    CURRENT_PROJECT_VERSION: .*/    CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml

echo
echo "==> 构建并打包"
bash scripts/package.sh "$VERSION" "$BUILD"

echo
echo "==> 提交版本号并打标签"
git add project.yml
git commit -m "chore(release): $TAG"
git tag -a "$TAG" -m "LENSO $TAG"
git push origin HEAD
git push origin "$TAG"

echo
echo "==> 创建 GitHub Release"
NOTES_FILE="$(mktemp)"
{
  echo "### 安装"
  echo "1. 下载 \`LENSO-$VERSION.dmg\`，打开后把 lenso 拖进「应用程序」。"
  echo "2. 本版本使用自签名证书，首次打开若提示「无法验证开发者」，"
  echo "   请在 Finder 中右键 App →「打开」，或执行："
  echo '   ```bash'
  echo "   xattr -dr com.apple.quarantine /Applications/lenso.app"
  echo '   ```'
  echo
  echo "### 变更"
  PREV="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
  if [ -n "$PREV" ]; then
    git log --no-merges --pretty=format:"- %s" "$PREV..$TAG"
  else
    git log --no-merges --pretty=format:"- %s" --max-count=30 "$TAG"
  fi
  echo
} > "$NOTES_FILE"

gh release create "$TAG" \
  "dist/LENSO-$VERSION.dmg" \
  "dist/LENSO-$VERSION.zip" \
  --repo "$REPO" \
  --title "LENSO $TAG" \
  --notes-file "$NOTES_FILE"

rm -f "$NOTES_FILE"

echo
echo "✅ 发布完成：https://github.com/$REPO/releases/tag/$TAG"
