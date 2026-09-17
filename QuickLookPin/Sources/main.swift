import Cocoa

// 把 stderr 重定向到固定日志文件。
// NSLog 写的是 stderr —— 从命令行启动时能直接看到，但用 open / 双击启动时
// stderr 没有去处，日志就丢了。重定向之后两种启动方式都能取证。
let logPath = (NSString(string: "~/Library/Logs/QuickLookPin.log").expandingTildeInPath as NSString).utf8String
freopen(logPath, "a", stderr)
setvbuf(stderr, nil, _IONBF, 0)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Info.plist 里已经有 LSUIElement，这里再显式设一次，防止从命令行裸跑二进制时冒出 Dock 图标
app.setActivationPolicy(.accessory)
app.run()
