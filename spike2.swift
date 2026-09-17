// 尖刀验证 v2：确认「多窗口互相独立」与「.normal / .compact 样式差异」
// 阶段 0 的第一问（第三方扩展能否在自建宿主里加载）已由 spike.swift 验证通过。
// 这里只补验 MVP 需求 3 的前提：一窗一实例、互不共享状态。
//
// 编译: xcrun swiftc -O -o spike2 spike2.swift -framework Cocoa -framework Quartz
// 运行: ./spike2 <文件1> [文件2 ...]

import Cocoa
import Quartz

setvbuf(stdout, nil, _IONBF, 0)

final class PinnedPreviewWindow: NSWindowController {
    let preview: QLPreviewView

    init(url: URL, index: Int, style: QLPreviewViewStyle, styleName: String) {
        let win = NSWindow(
            contentRect: NSRect(x: 60 + index * 460, y: 160, width: 440, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "📌 [\(styleName)] " + url.lastPathComponent
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        preview = QLPreviewView(frame: win.contentView!.bounds, style: style)!
        preview.autoresizingMask = [.width, .height]
        preview.shouldCloseWithWindow = false
        preview.previewItem = url as QLPreviewItem
        win.contentView?.addSubview(preview)

        super.init(window: win)
        print("窗口 #\(index) style=\(styleName) file=\(url.lastPathComponent) previewView=\(Unmanaged.passUnretained(preview).toOpaque())")
    }
    required init?(coder: NSCoder) { fatalError() }
}

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { print("用法: ./spike2 <文件...>"); exit(1) }
let urls = args.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
for u in urls where !FileManager.default.fileExists(atPath: u.path) {
    print("文件不存在: \(u.path)"); exit(1)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controllers: [PinnedPreviewWindow] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        // 同一个文件各开一个 .normal 和 .compact，再加上其余文件，验证互不干扰
        var i = 0
        for (style, name) in [(QLPreviewViewStyle.normal, "normal"), (.compact, "compact")] {
            let c = PinnedPreviewWindow(url: urls[0], index: i, style: style, styleName: name)
            c.showWindow(nil); c.window?.orderFrontRegardless()
            controllers.append(c); i += 1
        }
        for u in urls.dropFirst() {
            let c = PinnedPreviewWindow(url: u, index: i, style: .normal, styleName: "normal")
            c.showWindow(nil); c.window?.orderFrontRegardless()
            controllers.append(c); i += 1
        }
        NSApp.activate(ignoringOtherApps: true)

        let views = controllers.map { Unmanaged.passUnretained($0.preview).toOpaque() }
        print("共 \(controllers.count) 个窗口；QLPreviewView 实例地址互不相同 = \(Set(views.map { $0.hashValue }).count == views.count)")

        // 自动退出，避免留下僵尸进程
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            print("自动退出"); NSApp.terminate(nil)
        }
    }
    // 注意：不再让「关闭最后一个窗口就退出」，正式 App 是菜单栏常驻
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
