#!/bin/bash
# 构建 QuickLookPin.app
#
#   ./build.sh              本机架构构建（开发用，最快）
#   ./build.sh run          本机架构构建并启动
#   ./build.sh universal    通用二进制（arm64 + x86_64），发布用
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="QuickLookPin"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
MODE="${1:-native}"

# 编译单个架构
build_one() {
  local arch="$1" out="$2"
  xcrun swiftc -O \
    -target "${arch}-apple-macos13.0" \
    -o "$out" \
    Sources/*.swift \
    -framework Cocoa \
    -framework Quartz \
    -framework WebKit \
    -framework Carbon
}

echo "==> 清理"
rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$MODE" == "universal" ]]; then
  echo "==> 编译 arm64"
  build_one arm64 "$BUILD_DIR/.slice-arm64"
  echo "==> 编译 x86_64"
  build_one x86_64 "$BUILD_DIR/.slice-x86_64"
  echo "==> 合并为通用二进制"
  lipo -create -output "$APP/Contents/MacOS/$APP_NAME" \
    "$BUILD_DIR/.slice-arm64" "$BUILD_DIR/.slice-x86_64"
  rm -f "$BUILD_DIR/.slice-arm64" "$BUILD_DIR/.slice-x86_64"
else
  ARCH="$(uname -m)"
  echo "==> 编译 ($ARCH)"
  build_one "$ARCH" "$APP/Contents/MacOS/$APP_NAME"
fi

echo "==> 组装 bundle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# ad-hoc 签名。TCC（自动化权限）按签名标识记账，所以这一步不能省，
# 否则每次重建都可能被当成另一个 App 重新弹授权。
#
# 注意：ad-hoc 签名不是 Developer ID 签名，更不是公证。别人从网上下载后
# 仍会被 Gatekeeper 拦截，需要手动放行。要彻底消除警告必须做公证。
echo "==> ad-hoc 签名"
codesign --force --sign - --identifier "local.quicklookpin.$APP_NAME" "$APP"

echo "==> 校验"
lipo -info "$APP/Contents/MacOS/$APP_NAME" | sed 's/^/    /'
codesign -dv "$APP" 2>&1 | grep -E "Signature|Identifier" | sed 's/^/    /'

echo
echo "构建完成: $(cd "$BUILD_DIR" && pwd)/$APP_NAME.app"

if [[ "$MODE" == "run" ]]; then
  echo "==> 启动"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  open "$APP"
fi
