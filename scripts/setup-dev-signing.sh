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

# 注意：不能用 `security find-identity -p codesigning` 判断——它只列「受信任」的
# 身份，自签证书没手动设信任就不会出现在列表里，会导致每次重跑都重建一张新证书，
# 证书指纹一变，系统的屏幕录制授权又失效。这里按名字找证书本身。
if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "签名身份已存在：$CERT_NAME"
else
  echo "创建自签代码签名证书：$CERT_NAME"
  openssl req -x509 -newkey rsa:2048 \
    -config "$TMPDIR_SIGN/openssl.cnf" \
    -keyout "$TMPDIR_SIGN/key.pem" \
    -out "$TMPDIR_SIGN/cert.pem" \
    -days 3650 -nodes >/dev/null 2>&1

  # macOS 的 security import 只认传统 PKCS#12（RC2/3DES 加密 + SHA1 MAC）。
  # Homebrew 的 OpenSSL 3+/4+ 默认用 AES-256 + PBKDF2，导入时会报
  #   SecKeychainItemImport: MAC verification failed during PKCS12 import
  # 所以这里显式指定传统算法（-legacy 在部分版本不存在，用 PBE 参数兜底）。
  export_p12() {
    openssl pkcs12 -export -legacy \
      -inkey "$TMPDIR_SIGN/key.pem" \
      -in "$TMPDIR_SIGN/cert.pem" \
      -out "$TMPDIR_SIGN/cert.p12" \
      -passout pass:lenso >/dev/null 2>&1 && return 0
    openssl pkcs12 -export \
      -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
      -inkey "$TMPDIR_SIGN/key.pem" \
      -in "$TMPDIR_SIGN/cert.pem" \
      -out "$TMPDIR_SIGN/cert.p12" \
      -passout pass:lenso >/dev/null 2>&1
  }
  export_p12

  security import "$TMPDIR_SIGN/cert.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P lenso -T /usr/bin/codesign -T /usr/bin/security
  echo "已导入钥匙串。"
fi

echo
echo "本机可用的代码签名身份："
security find-identity -v -p codesigning | sed 's/^/  /'
echo "  （自签证书 $CERT_NAME 不在上面的列表里是正常的：它没有手动设为受信任，"
echo "    但 codesign 依然能用它签名，且签名指纹稳定，屏幕录制授权不会因重建而失效）"

# 可以传一个 .app 路径进来（build.sh 会传）；不传就自动找最新的构建产物
APP_PATH="${1:-$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/LENSO-*/Build/Products/Debug/*.app 2>/dev/null | head -1 || true)}"
if [ -n "$APP_PATH" ]; then
  echo
  echo "使用固定身份重新签名：$APP_PATH"
  codesign --force --sign "$CERT_NAME" "$APP_PATH"
  codesign -dv "$APP_PATH" 2>&1 | grep -E "Identifier|Authority" || true
  echo "签名要求（重建后应保持不变）："
  codesign -d -r- "$APP_PATH" 2>&1 | grep designated | sed 's/^/  /'
else
  echo "未找到已构建的 LENSO.app。"
fi

echo
echo "完成。之后构建请用："
echo "  bash scripts/build.sh"
echo
echo "（不能直接 xcodebuild：项目没有 DEVELOPMENT_TEAM，Xcode 会强制 ad-hoc 签名，"
echo "  命令行传 CODE_SIGN_IDENTITY 也会被覆盖。ad-hoc 的签名要求是 cdhash，"
echo "  每次编译都变，屏幕录制授权就每次都要重给。）"
echo
echo "授权只需一次：系统设置 → 隐私与安全性 → 屏幕录制 → 移除旧的 lenso 条目，"
echo "重新触发截图后再打开新的 lenso 开关。"
