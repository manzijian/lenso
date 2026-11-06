#!/bin/bash
# LENSO 开发期固定签名
#
# 目的：Xcode 默认对调试构建使用 ad-hoc 签名，每次重新编译 cdhash 都会变化，
# macOS 会把它们当成不同的 App，导致“屏幕录制”权限每次重建后失效、需要重新授权。
# 本脚本在登录钥匙串里创建一个自签证书（含 codeSigning EKU），用它给 App 签名；
# 之后只要始终用这个身份签名，系统授权只需一次。
#
# 用法：
#   bash scripts/setup-dev-signing.sh
#
# 若弹出“codesign 想要使用私钥”，请选择“始终允许”。

set -euo pipefail

CERT_NAME="LENSO Dev Signing"
TMPDIR_SIGN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SIGN"' EXIT

cat > "$TMPDIR_SIGN/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3_req
prompt = no

[dn]
CN = LENSO Dev Signing

[v3_req]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "签名身份已存在：$CERT_NAME"
else
  echo "创建自签代码签名证书：$CERT_NAME"
  openssl req -x509 -newkey rsa:2048 \
    -config "$TMPDIR_SIGN/openssl.cnf" \
    -keyout "$TMPDIR_SIGN/key.pem" \
    -out "$TMPDIR_SIGN/cert.pem" \
    -days 3650 -nodes >/dev/null 2>&1

  openssl pkcs12 -export \
    -inkey "$TMPDIR_SIGN/key.pem" \
    -in "$TMPDIR_SIGN/cert.pem" \
    -out "$TMPDIR_SIGN/cert.p12" \
    -passout pass:lenso >/dev/null 2>&1

  security import "$TMPDIR_SIGN/cert.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P lenso -T /usr/bin/codesign -T /usr/bin/security
  echo "已导入钥匙串。"
fi

echo
echo "可用签名身份："
security find-identity -v -p codesigning | sed 's/^/  /'

APP_PATH="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/LENSO-*/Build/Products/Debug/LENSO.app 2>/dev/null | head -1 || true)"
if [ -n "$APP_PATH" ]; then
  echo
  echo "使用固定身份重新签名：$APP_PATH"
  codesign --force --deep --sign "$CERT_NAME" "$APP_PATH"
  codesign -dv "$APP_PATH" 2>&1 | grep -E "Identifier|Authority" || true
else
  echo "未找到已构建的 LENSO.app。"
fi

echo
echo "完成。之后构建请使用："
echo "  CODE_SIGN_IDENTITY=\"$CERT_NAME\" xcodebuild -project LENSO.xcodeproj -scheme LENSO -configuration Debug build"
echo
echo "授权只需一次：系统设置 → 隐私与安全性 → 屏幕录制 → 移除旧的 LENSO 条目，"
echo "重新触发截图后再打开新的 LENSO 开关。"
