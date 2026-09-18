import Cocoa
import Quartz

/// LSUIElement 的 App 没有菜单栏，⌘W 不会经过菜单派发，所以在窗口这层自己接。
final class PinnedWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// 窗口常以「不激活」方式弹出（不抢 Finder 焦点）。这时第一下点击只会激活 App，
    /// 拖选文字不生效，看起来就像「选不中」。这里在按下时先把 App 和窗口激活，
    /// 让同一下拖动直接开始选取。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !NSApp.isActive || !isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            makeKey()
        }
        super.sendEvent(event)
    }
}

/// 一个预览窗口。一窗一实例，和其他窗口不共享任何状态。
///
/// 两种状态：
/// - **跟随中**：内容随 Finder 当前选中项变化（在 Finder 里按上下键就切内容）
/// - **已锁定**：钉死在某个文件上，Finder 再怎么切都不受影响
///
/// 标题栏两个按钮各管一件事，不要混：
/// - 图钉    → 跟随 / 锁定（内容层面）
/// - 方块箭头 → 置顶 / 普通（窗口层级）
final class PinnedPreviewWindowController: NSWindowController, NSWindowDelegate {

    private(set) var url: URL
    private(set) var isFollowing: Bool
    private var isFloating = true

    private let preview: QLPreviewView
    private var watcher: FileWatcher?
    private var pinButton: NSButton?
    private var floatButton: NSButton?

    var onClose: ((PinnedPreviewWindowController) -> Void)?
    /// 跟随状态被用户切换时回调，AppDelegate 据此维护「当前跟随窗」
    var onFollowingChanged: ((PinnedPreviewWindowController) -> Void)?

    private static var cascadeIndex = 0

    init(url: URL, following: Bool) {
        self.url = url
        self.isFollowing = following

        let size = NSSize(width: 820, height: 680)
        let frame = PinnedPreviewWindowController.nextCascadeFrame(size: size)

        let window = PinnedWindow(contentRect: frame,
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered,
                                  defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 320, height: 240)

        // 阶段 0 结论：必须用 .normal。.compact 只给一张文档图标缩略图，
        // 拿不到第三方扩展的完整渲染。
        guard let view = QLPreviewView(frame: window.contentView!.bounds, style: .normal) else {
            fatalError("QLPreviewView 创建失败")
        }
        view.autoresizingMask = [.width, .height]
        view.shouldCloseWithWindow = false
        view.previewItem = url as QLPreviewItem
        window.contentView?.addSubview(view)
        self.preview = view

        super.init(window: window)
        window.delegate = self
        SelectionEnabler.applyRepeatedly(to: view)
        installTitlebarButtons()
        rebuildWatcher()
        updateChrome()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // MARK: - 跟随

    /// 跟随模式下切换到新文件。已锁定的窗口会忽略此调用。
    func follow(url newURL: URL) {
        guard isFollowing, newURL != url else { return }
        url = newURL
        preview.previewItem = newURL as QLPreviewItem
        // 换了文件就是换了一套视图，选取开关要重新打一遍
        SelectionEnabler.applyRepeatedly(to: preview)
        rebuildWatcher()
        updateChrome()
    }

    /// 由外部（AppDelegate）静默改状态，不触发 onFollowingChanged，避免回调打环
    func setFollowing(_ value: Bool) {
        guard isFollowing != value else { return }
        isFollowing = value
        updateChrome()
    }

    // MARK: - 文件变更监视

    private func rebuildWatcher() {
        watcher?.stop()
        watcher = nil
        guard Settings.watchFileChanges else { return }
        watcher = FileWatcher(url: url) { [weak self] in
            guard let self else { return }
            self.preview.refreshPreviewItem()
            SelectionEnabler.applyRepeatedly(to: self.preview)
        }
    }

    // MARK: - 层叠偏移

    private static func nextCascadeFrame(size: NSSize) -> NSRect {
        // 用鼠标所在的那块屏，而不是 NSScreen.main。
        // NSScreen.main 的语义是「键盘焦点所在的屏幕」而非「主显示器」，
        // 多显示器下会把窗口甩到用户没在看的那块屏上。
        let cursor = NSEvent.mouseLocation
        let target = NSScreen.screens.first { $0.frame.contains(cursor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let screen = target?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let step: CGFloat = 28
        let i = CGFloat(cascadeIndex % 10)
        cascadeIndex += 1

        let w = min(size.width, screen.width - 40)
        let h = min(size.height, screen.height - 40)
        var x = screen.minX + 60 + i * step
        var y = screen.maxY - h - 40 - i * step
        x = min(x, screen.maxX - w - 20)
        y = max(y, screen.minY + 20)
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - 标题栏按钮

    private func installTitlebarButtons() {
        let pin = NSButton(frame: NSRect(x: 2, y: 0, width: 26, height: 22))
        pin.isBordered = false
        pin.imagePosition = .imageOnly
        pin.target = self
        pin.action = #selector(togglePin)
        pinButton = pin

        let float = NSButton(frame: NSRect(x: 30, y: 0, width: 26, height: 22))
        float.isBordered = false
        float.imagePosition = .imageOnly
        float.target = self
        float.action = #selector(toggleFloat)
        floatButton = float

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 22))
        container.addSubview(pin)
        container.addSubview(float)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .right
        window?.addTitlebarAccessoryViewController(accessory)
    }

    @objc private func togglePin() {
        isFollowing.toggle()
        updateChrome()
        onFollowingChanged?(self)
    }

    @objc private func toggleFloat() {
        isFloating.toggle()
        window?.level = isFloating ? .floating : .normal
        updateChrome()
    }

    private func updateChrome() {
        pinButton?.image = NSImage(systemSymbolName: isFollowing ? "pin.slash" : "pin.fill",
                                   accessibilityDescription: isFollowing ? "锁定当前文件" : "恢复跟随")
        pinButton?.toolTip = isFollowing
            ? "跟随 Finder 选中项中（点击锁定在当前文件）"
            : "已锁定在当前文件（点击恢复跟随）"

        floatButton?.image = NSImage(systemSymbolName: isFloating ? "arrow.up.square.fill" : "arrow.up.square",
                                     accessibilityDescription: isFloating ? "取消置顶" : "置顶")
        floatButton?.toolTip = isFloating ? "当前：置顶（点击改为普通窗口）" : "当前：普通（点击改为置顶）"

        window?.title = (isFollowing ? "◎ 跟随 · " : "📌 ") + url.lastPathComponent
    }

    // MARK: -

    func show(activating: Bool) {
        if activating {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 不抢 Finder 的焦点，只把窗口摆到前面。
            // 跟随模式下这一条尤其重要：抢了焦点就没法在 Finder 里按上下键了。
            window?.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSLog("[QuickLookPin] 窗口关闭 \(url.lastPathComponent)")
        watcher?.stop()
        watcher = nil

        // 因为设了 shouldCloseWithWindow = false，QLPreviewView 不会自己收尾。
        // 必须显式 close()，否则它持有的预览资源不释放 —— 实测反复开关窗口时
        // 内存呈线性上涨（约 0.15 MB/窗口），这里是头号嫌疑。
        preview.close()
        preview.removeFromSuperview()

        onClose?(self)
    }
}
