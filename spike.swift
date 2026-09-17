// 尖刀验证：QLPreviewView 能否复用第三方 Quick Look 扩展的渲染结果
// 编译: swiftc -o spike spike.swift -framework Cocoa -framework Quartz
// 运行: ./spike /path/to/file.md

import Cocoa
import Quartz

final class PinnedPreviewWindow: NSWindowController {
    init(url: URL, index: Int) {
        let win = NSWindow(
            contentRect: NSRect(x: 100 + index * 40, y: 100 + index * 40, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "📌 " + url.lastPathComponent
        win.level = .floating                 // 永远浮在最上层
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let preview = QLPreviewView(frame: win.contentView!.bounds, style: .normal)!
        preview.autoresizingMask = [.width, .height]
        preview.shouldCloseWithWindow = false
        preview.previewItem = url as QLPreviewItem
        win.contentView?.addSubview(preview)

        super.init(window: win)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controllers: [PinnedPreviewWindow] = []
    let urls: [URL]
    init(urls: [URL]) { self.urls = urls }

    func applicationDidFinishLaunching(_ n: Notification) {
        for (i, u) in urls.enumerated() {
            let c = PinnedPreviewWindow(url: u, index: i)
            c.showWindow(nil)
            controllers.append(c)
            print("opened: \(u.path)")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let args = CommandLine.arguments.dropFirst()
guard !args.isEmpty else {
    print("用法: ./spike <文件路径> [更多文件...]")
    exit(1)
}
let urls = args.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
for u in urls where !FileManager.default.fileExists(atPath: u.path) {
    print("文件不存在: \(u.path)"); exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate(urls: urls)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
