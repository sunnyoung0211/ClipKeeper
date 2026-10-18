#!/bin/bash
# 一次性设置"固定签名"：生成一张只用于代码签名的自签名证书，以后打包安装包都用它签名。
#
# 为什么需要固定签名？
#   macOS 是按"签名"来认应用的。临时签名（ad-hoc）每次编译都不一样，系统会把每个新版本都当成
#   一个新应用，用户每次升级后都要重新授权辅助功能。用同一张证书签名后，系统就能认出是同一个应用，
#   授权会一直保留。
#
# 用法（在项目根目录运行，每台用来打包的 Mac 运行一次）：
#   ./scripts/setup-signing.sh
#
# 它会做这些事：
#   1. 生成证书和私钥，证书名叫 "ClipKeeper Code Signing"，不包含任何个人信息；
#      备份文件放在 ~/.clipkeeper-signing/（换了新 Mac 时，把这个文件夹拷过去再运行一次，就会用回同一张证书）
#   2. 导入"登录"钥匙串（和 Xcode 的 Apple Development 证书放在一起），codesign 才能找到它
#
# 这是自签名证书，系统不会"信任"它（钥匙串里会显示 CSSMERR_TP_NOT_TRUSTED），这是正常的：
# 签名、校验签名、保留辅助功能授权都不需要它被信任，所以不用去改证书的信任设置。
#
# ~/.clipkeeper-signing/ 里的文件（可以用环境变量 CLIPKEEPER_SIGNING_DIR 换位置）：
#   identity.p12           证书 + 私钥的备份（加了密码）
#   identity-password.txt  上面这个备份文件的密码
#   certificate.pem        证书本身（公开信息）
#
# ⚠️ 请把这个文件夹备份到安全的地方，并且绝对不要提交到 Git 或发给别人：
#   - 丢了它：只能重新生成，用户升级到用新证书签名的版本时需要重新授权一次，
#     而且已安装的版本会因为"签名不一致"拒绝自动更新，需要手动下载一次；
#   - 泄露了：别人可以冒充 ClipKeeper 签名，继承用户给 ClipKeeper 的辅助功能权限。
#
# 不想用了：在「钥匙串访问 → 登录 → 我的证书」里删除 ClipKeeper Code Signing（会一起删掉私钥），
# 再删除整个文件夹即可。
set -euo pipefail

NAME="ClipKeeper Code Signing"
BACKUP_DIR="${CLIPKEEPER_SIGNING_DIR:-$HOME/.clipkeeper-signing}"
P12="$BACKUP_DIR/identity.p12"
P12_PASSWORD_FILE="$BACKUP_DIR/identity-password.txt"
CERT="$BACKUP_DIR/certificate.pem"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl   # 用系统自带的 openssl，它生成的 .p12 文件钥匙串一定能导入

# 登录钥匙串里有没有这张证书
has_certificate() {
  security find-certificate -c "$NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1
}
# 能不能用来签名：证书和私钥都在。
# 注意不能加 -v 参数：-v 只列出"受信任"的证书，而自签名证书本来就不受信任，但照样能签名
can_sign() {
  grep -q "\"$NAME\"" <<< "$(security find-identity -p codesigning "$LOGIN_KEYCHAIN")"
}

if has_certificate; then
  echo "▶ 登录钥匙串里已经有 $NAME 了"
else
  if [ -f "$P12" ]; then
    echo "▶ 找到之前的备份，导入同一张证书：$P12"
  else
    echo "▶ 生成证书和私钥…"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"   # 只有你自己能读这个文件夹
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT   # 结束时删掉临时文件（包括没加密的私钥）

    # 证书的内容：名字、用途只能是"代码签名"、有效期 20 年
    cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = ext
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 7300 \
      -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$CERT" 2>/dev/null
    # 打包成加了密码的 .p12 文件（证书 + 私钥），既用来导入钥匙串，也是备份
    ( umask 077; "$OPENSSL" rand -hex 16 | tr -d '\n' > "$P12_PASSWORD_FILE" )
    "$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$CERT" \
      -out "$P12" -passout "file:$P12_PASSWORD_FILE"
    chmod 600 "$P12"
  fi

  echo "▶ 导入登录钥匙串…"
  # -T：允许 codesign 使用这个私钥，打包时不用每次都确认
  security import "$P12" -k "$LOGIN_KEYCHAIN" -P "$(cat "$P12_PASSWORD_FILE")" -T /usr/bin/codesign >/dev/null
fi

if ! can_sign; then
  echo "❌ 登录钥匙串里有证书，但找不到对应的私钥。请在「钥匙串访问」里删除 $NAME 后重新运行这个脚本"
  exit 1
fi

echo "✅ 固定签名已设置好。以后运行 ./scripts/make-dmg.sh 打包时会自动使用它"
echo "   请把这个文件夹备份到安全的地方（不要提交到 Git）：$BACKUP_DIR"
