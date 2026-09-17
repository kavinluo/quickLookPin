#!/bin/bash
# 一条命令构建出可运行的 QuickLookPin.app
#   ./build.sh          构建
#   ./build.sh run      构建并启动
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="QuickLookPin"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
ARCH="$(uname -m)"

echo "==> 清理"
rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 ($ARCH)"
xcrun swiftc -O \
  -target "${ARCH}-apple-macos13.0" \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  Sources/*.swift \
  -framework Cocoa \
  -framework Quartz \
  -framework Carbon

echo "==> 组装 bundle"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# ad-hoc 签名。TCC（自动化权限）按签名标识记账，所以这一步不能省，
# 否则每次重建都可能被当成另一个 App 重新弹授权。
echo "==> ad-hoc 签名"
codesign --force --sign - --identifier "local.quicklookpin.$APP_NAME" "$APP"
codesign -dv "$APP" 2>&1 | sed 's/^/    /'

echo
echo "构建完成: $(cd "$BUILD_DIR" && pwd)/$APP_NAME.app"

if [[ "${1:-}" == "run" ]]; then
  echo "==> 启动"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  open "$APP"
fi
