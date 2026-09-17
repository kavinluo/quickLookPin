#!/bin/bash
# 打包发布用的 zip
#
#   ./release.sh v0.1.0
#
# 产出 build/QuickLookPin-<版本>-universal.zip 并打印 SHA256。
#
# 关于签名：当前只做 ad-hoc 签名，**没有公证**，别人下载后首次打开会被
# Gatekeeper 拦截。要做正式发布，在「ad-hoc 签名」那步之后补上：
#
#   codesign --force --options runtime --timestamp \
#     --sign "Developer ID Application: <你的名字> (<TeamID>)" "$APP"
#   xcrun notarytool submit "$ZIP" --keychain-profile "AC_PASSWORD" --wait
#   xcrun stapler staple "$APP"      # 然后重新打 zip
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

echo "==> 构建通用二进制"
./build.sh universal

echo
echo "==> 校验架构"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")
echo "    包含架构: $ARCHS"
for need in arm64 x86_64; do
  if ! echo "$ARCHS" | grep -qw "$need"; then
    echo "    ❌ 缺少 $need，中止"
    exit 1
  fi
done
echo "    ✅ arm64 与 x86_64 都在"

echo
echo "==> 打包"
rm -f "$ZIP"
# 用 ditto 而不是 zip：能正确保留 bundle 结构、符号链接和扩展属性
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "==> 结果"
echo "    文件: $ZIP"
echo "    大小: $(du -h "$ZIP" | awk '{print $1}')"
echo "    SHA256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo
echo "    签名状态: $(codesign -dv "$APP" 2>&1 | grep -E '^Signature' || echo '未知')"
echo "    ⚠️  未公证 —— 下载者首次打开需在「系统设置 → 隐私与安全性」点「仍要打开」"
