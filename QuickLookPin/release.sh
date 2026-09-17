#!/bin/bash
# 打包发布用的 zip，可选做 Developer ID 签名与 Apple 公证。
#
#   ./release.sh v0.1.0                 只打包（ad-hoc 签名，未公证）
#   SIGN=1 ./release.sh v0.1.0          额外做 Developer ID 签名（仍未公证）
#   SIGN=1 NOTARY=AC_PASSWORD ./release.sh v0.1.0    签名 + 公证 + staple
#
# 可用环境变量：
#   SIGN_IDENTITY   指定签名身份；不指定则自动挑第一个 Developer ID Application
#   NOTARY          notarytool 的钥匙串 profile 名字；给了才会做公证
#
# 首次使用公证前，需要你自己存一次凭据（会安全地交互提示，不要把密码写进脚本）：
#
#   xcrun notarytool store-credentials "AC_PASSWORD" \
#     --apple-id "<你的 Apple ID>" \
#     --team-id "<10 位 Team ID>" \
#     --password "<app-specific password>"
#
# app-specific password 在 https://account.apple.com → 登录与安全 → App 专用密码 生成。
#
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "用法: ./release.sh v0.1.0"
  exit 1
fi

APP_NAME="QuickLookPin"
APP="build/$APP_NAME.app"
ZIP="build/${APP_NAME}-${VERSION}-universal.zip"
ENTITLEMENTS="Resources/$APP_NAME.entitlements"

# ---------------------------------------------------------------- 构建

echo "==> 构建通用二进制"
./build.sh universal

echo
echo "==> 校验架构"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")
echo "    包含架构: $ARCHS"
for need in arm64 x86_64; do
  echo "$ARCHS" | grep -qw "$need" || { echo "    ❌ 缺少 $need，中止"; exit 1; }
done
echo "    ✅ arm64 与 x86_64 都在"

# ---------------------------------------------------------------- 签名

NOTARIZED=0
if [[ "${SIGN:-0}" == "1" ]]; then
  IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')}"

  if [[ -z "$IDENTITY" ]]; then
    echo
    echo "    ❌ 找不到 Developer ID Application 证书，无法做分发签名。"
    echo "       需要付费的 Apple Developer 账号并在钥匙串里装好证书。"
    exit 1
  fi

  [[ -f "$ENTITLEMENTS" ]] || { echo "    ❌ 缺少 $ENTITLEMENTS"; exit 1; }

  echo
  echo "==> Developer ID 签名（含 Hardened Runtime）"
  echo "    身份: $IDENTITY"
  # --options runtime 开启 Hardened Runtime（公证的硬性要求）
  # --entitlements   放行 Apple Event，否则读不到 Finder 选中项
  # --timestamp      打安全时间戳，公证要求
  codesign --force --deep \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$APP"

  echo "    校验签名:"
  codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/      /'
  echo "    flags（应含 runtime）: $(codesign -dv "$APP" 2>&1 | grep '^CodeDirectory' | sed -E 's/.*flags=([^ ]+).*/\1/')"
  echo "    entitlements:"
  codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | plutil -convert xml1 -o - - 2>/dev/null | grep -A1 apple-events | sed 's/^/      /' || true
fi

# ---------------------------------------------------------------- 打包

echo
echo "==> 打包"
rm -f "$ZIP"
# 用 ditto 而不是 zip：能正确保留 bundle 结构、符号链接和扩展属性
ditto -c -k --keepParent "$APP" "$ZIP"

# ---------------------------------------------------------------- 公证

if [[ -n "${NOTARY:-}" ]]; then
  echo
  echo "==> 提交公证（profile: $NOTARY），这一步通常要几分钟"
  if ! xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY" --wait 2>&1 | tee /tmp/_notary.log; then
    echo "    ❌ 公证失败"
    SUB=$(grep -oE '[0-9a-f-]{36}' /tmp/_notary.log | head -1)
    [[ -n "$SUB" ]] && xcrun notarytool log "$SUB" --keychain-profile "$NOTARY" 2>&1 | head -40
    exit 1
  fi
  grep -q "status: Accepted" /tmp/_notary.log || { echo "    ❌ 公证未通过，详见上面输出"; exit 1; }

  echo
  echo "==> staple（把公证票据钉进 App，之后离线也能验证）"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP" && NOTARIZED=1

  echo "==> 重新打包（zip 必须包含 staple 之后的 App）"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

# ---------------------------------------------------------------- 结果

echo
echo "==> 结果"
echo "    文件: $ZIP"
echo "    大小: $(du -h "$ZIP" | awk '{print $1}')"
echo "    SHA256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "    架构: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
# 注意：必须用 -dvvv，-dv 不会输出 Authority 行（早先这里报错成 ad-hoc 就是因为这个）
AUTH=$(codesign -dvvv "$APP" 2>&1 | grep '^Authority=' | head -1 | sed 's/^Authority=//')
TEAM=$(codesign -dvvv "$APP" 2>&1 | grep '^TeamIdentifier=' | head -1 | sed 's/^TeamIdentifier=//')
echo "    签名: ${AUTH:-ad-hoc（未做分发签名）}"
echo "    Team: ${TEAM:-无}"

if [[ "$NOTARIZED" == "1" ]]; then
  echo
  echo "    ✅ 已公证并 staple —— 下载者双击即可打开，没有任何警告"
  echo "    Gatekeeper 评估:"
  spctl -a -vvv -t install "$APP" 2>&1 | sed 's/^/      /'
else
  echo
  echo "    ⚠️  未公证 —— 下载者首次打开需在「系统设置 → 隐私与安全性」点「仍要打开」"
  echo "       要消除警告：先存好凭据，再用 SIGN=1 NOTARY=<profile> 重跑本脚本"
fi
