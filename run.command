#!/bin/bash
cd "$(dirname "$0")"
exec > >(tee -a spike.log) 2>&1
echo "=============== $(date) ==============="
echo "--- system ---"
sw_vers
echo "--- swiftc ---"
xcrun --find swiftc 2>&1 || echo "NO SWIFTC — 需要安装 Xcode Command Line Tools"
echo "--- 已安装的 Quick Look 预览扩展 ---"
pluginkit -mAvvv -p com.apple.quicklook.preview 2>&1 | head -40
echo "--- 旧式 qlgenerator ---"
ls -1 ~/Library/QuickLook /Library/QuickLook 2>/dev/null
echo "--- 编译 ---"
xcrun swiftc -O -o spike spike.swift -framework Cocoa -framework Quartz 2>&1 || { echo "编译失败"; exit 1; }
echo "编译成功"
echo "--- 运行 ---"
./spike "$PWD/test.md" &
SPIKE_PID=$!
sleep 5
screencapture -x -o shot.png
echo "截图已保存 shot.png"
sleep 25
kill $SPIKE_PID 2>/dev/null
echo "=============== done ==============="
