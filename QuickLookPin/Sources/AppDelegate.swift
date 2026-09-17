import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var hotKeyManager: HotKeyManager!
    private var preferences: PreferencesWindowController?

    /// 所有预览窗口（含跟随窗和已锁定的窗口）
    private var windows: [PinnedPreviewWindowController] = []
    /// 当前那个「跟随 Finder 选中项」的窗口，同一时刻最多一个
    private weak var followWindow: PinnedPreviewWindowController?

    /// 注册失败 / 被系统占用时记下来，在菜单里显示
    private var hotKeyProblem: String?

    private lazy var selectionWatcher: FinderSelectionWatcher = {
        let w = FinderSelectionWatcher { [weak self] urls in
            // 选中被清空时保持当前内容不变，不要把窗口刷成空白
            guard let first = urls.first else { return }
            self?.followWindow?.follow(url: first)
        }
        w.onPersistentFailure = { [weak self] error in
            self?.presentAlert(title: "跟随模式已停止", message: error.localizedMessage)
        }
        return w
    }()

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()

        hotKeyManager = HotKeyManager { [weak self] in
            self?.pinCurrentFinderSelection()
        }
        applyHotKey(Settings.hotKey)

        // 调试入口：--pin <路径...>
        // 绕开 Finder 和自动化权限，直接开锁定窗口，用来单独验证窗口行为。
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--pin" {
            let urls = args.dropFirst().map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                for url in urls { self?.makeWindow(url: url, following: false) }
                self?.rebuildMenu()
            }
        }

        // 调试入口：--mem-test <文件1> <文件2> ...
        // 反复开关窗口 3 轮，每轮记录内存足迹。
        // 判据：「全部关闭后」的数字如果逐轮上涨，说明有泄漏。
        if args.first == "--mem-test" {
            var rest = Array(args.dropFirst())
            var rounds = 3
            // 可选的首个数字参数指定轮数：--mem-test 10 <文件...>
            if let first = rest.first, let n = Int(first) {
                rounds = max(1, n)
                rest.removeFirst()
            }
            let urls = rest.map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.runMemoryTest(urls, rounds: rounds)
            }
        }

        // 调试入口：--poll-bench <文件> [秒数]
        // 纯轮询开销基准：开一个跟随窗、把 Finder 拉到前台，然后**什么都不做**。
        // 和 --follow-test 的区别很关键：那个脚本会不停开 Finder 窗口、改选中项、
        // 开预览窗口，这些动作本身的 CPU 开销会把轮询的开销淹没，测不准。
        if args.first == "--poll-bench", args.count >= 2 {
            let url = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath)
            let seconds = args.count >= 3 ? (Double(args[2]) ?? 30) : 30
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.runPollBench(url: url, seconds: seconds)
            }
        }

        // 调试入口：--follow-test <文件夹> <文件1> <文件2> ...
        // 用 App 自己已获授权的 Apple Event 去切 Finder 选中项，自测跟随模式，
        // 不需要额外权限也不需要人按键。会激活 Finder 并改动其选中项。
        if args.first == "--follow-test" {
            let urls = args.dropFirst().map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.runFollowSelfTest(urls)
            }
        }
    }

    /// 跟随模式自测。第一个参数是文件夹，其余是该文件夹下要依次选中的文件。
    private func runFollowSelfTest(_ urls: [URL]) {
        guard urls.count >= 3 else {
            NSLog("[自测] 用法: --follow-test <文件夹> <文件1> <文件2> ...")
            return
        }
        let folder = urls[0]
        let files = Array(urls.dropFirst())

        // 锁屏 / 睡眠时 Finder 无法被 activate，轮询的前台门槛永远不满足，
        // 整个测试会得出一堆没有意义的「没跟上」。直接中止，别产出误导性结论。
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "未知"
        if front == "com.apple.loginwindow" {
            NSLog("[自测] ⛔ 中止：前台是 loginwindow，屏幕处于锁定/睡眠状态，"
                  + "Finder 无法被激活。请解锁屏幕后重跑。")
            return
        }
        NSLog("[自测] 环境检查通过，当前前台 = \(front)")

        NSLog("[自测] 打开 Finder 窗口: \(folder.path)")
        if let e = FinderSelection.openFolder(folder) {
            NSLog("[自测] ❌ 打开文件夹失败: \(e)"); return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            if let e = FinderSelection.select(files[0]) {
                NSLog("[自测] ❌ 初次选中失败: \(e)"); return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.pinCurrentFinderSelection()
                NSLog("[自测] 跟随窗已开，当前显示 = \(self.followWindow?.url.lastPathComponent ?? "无")")

                // 依次切到后面每个文件，再切回第一个，每次都校验跟随窗是否跟上
                // 只往后切，**不绕回第一个文件**。
                // 之前的版本末尾会切回 files[0]，而窗口本来显示的就是 files[0]，
                // 于是「窗口压根没变」也会被判成 ✅ 通过 —— 是个假通过，已去掉。
                var delay = 1.5
                var previousExpected = files[0].lastPathComponent
                for target in files.dropFirst() {
                    let prev = previousExpected
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if let e = FinderSelection.select(target) {
                            NSLog("[自测] ❌ 切到 \(target.lastPathComponent) 失败: \(e)")
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.5) {
                        // 锁屏时 Finder 无法被激活，轮询不会发事件，此时判「没跟上」是误判
                        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                        if front == "com.apple.loginwindow" {
                            NSLog("[自测] ⛔ 本次不可判定：屏幕已锁定（前台=loginwindow）")
                            return
                        }
                        let shown = self.followWindow?.url.lastPathComponent ?? "无"
                        let ok = shown == target.lastPathComponent
                        NSLog("[自测] 上一个=\(prev) 期望=\(target.lastPathComponent) 实际=\(shown) "
                              + "\(ok ? "✅ 跟上了" : "❌ 没跟上")")
                    }
                    previousExpected = target.lastPathComponent
                    delay += 3.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NSLog("[自测] 结束，关掉临时 Finder 窗口")
                    FinderSelection.closeFrontWindow()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionWatcher.stop()
        hotKeyManager?.unregister()
    }

    // MARK: - 菜单栏

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pin.circle",
                                           accessibilityDescription: "QuickLookPin")
        statusItem.button?.toolTip = "QuickLookPin"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let title = followWindow == nil
            ? "打开跟随预览窗口　\(Settings.hotKey.displayString)"
            : "显示跟随窗口　\(Settings.hotKey.displayString)"
        let openItem = NSMenuItem(title: title,
                                  action: #selector(pinCurrentFinderSelection),
                                  keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        if followWindow != nil {
            let hint = NSMenuItem(title: "　跟随中：在 Finder 里按上下键即可切换内容",
                                  action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        if let problem = hotKeyProblem {
            let warn = NSMenuItem(title: "⚠️ 快捷键未生效：\(problem)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        menu.addItem(.separator())

        let closeAll = NSMenuItem(title: "关闭所有预览窗口（\(windows.count)）",
                                  action: #selector(closeAllWindows),
                                  keyEquivalent: "")
        closeAll.target = self
        closeAll.isEnabled = !windows.isEmpty
        menu.addItem(closeAll)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "偏好设置…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let quit = NSMenuItem(title: "退出 QuickLookPin", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - 快捷键

    private func applyHotKey(_ spec: HotKeySpec) {
        if let status = hotKeyManager.register(spec) {
            hotKeyProblem = HotKeyManager.describe(status)
            NSLog("[QuickLookPin] 热键 \(spec.displayString) 注册失败：\(hotKeyProblem!)")
        } else if let conflict = SystemHotKeyConflict.conflictName(for: spec) {
            // 注册成功 ≠ 按下有效：系统快捷键会先把按键截走
            hotKeyProblem = "被系统「\(conflict)」占用，按下不会触发"
            NSLog("[QuickLookPin] 热键 \(spec.displayString) 注册成功，但被系统「\(conflict)」占用，按下收不到")
        } else {
            hotKeyProblem = nil
            NSLog("[QuickLookPin] 热键 \(spec.displayString) 注册成功且无系统冲突")
        }
        rebuildMenu()
    }

    // MARK: - 核心动作

    @objc func pinCurrentFinderSelection() {
        // 已经有一个还没锁定的跟随窗，就不再开新的，只把它拉到前面并强制刷新一次
        if let existing = followWindow {
            selectionWatcher.forceNextUpdate()
            existing.show(activating: Settings.activateOnOpen)
            return
        }

        switch FinderSelection.current() {
        case .failure(let error):
            presentAlert(title: "读取 Finder 选中项失败", message: error.localizedMessage)

        case .success(let urls):
            guard let first = urls.first else {
                NSSound.beep()   // 没选中东西，不弹框打断
                return
            }
            let controller = makeWindow(url: first, following: true)
            followWindow = controller
            selectionWatcher.start()
            rebuildMenu()
        }
    }

    @discardableResult
    private func makeWindow(url: URL, following: Bool) -> PinnedPreviewWindowController {
        let controller = PinnedPreviewWindowController(url: url, following: following)
        controller.onClose = { [weak self] c in self?.forget(c) }
        controller.onFollowingChanged = { [weak self] c in self?.followingChanged(c) }
        windows.append(controller)
        controller.show(activating: Settings.activateOnOpen)
        NSLog("[QuickLookPin] 已打开窗口 \(url.path) following=\(following)")
        return controller
    }

    /// 用户点了图钉：跟随 ⇄ 锁定
    private func followingChanged(_ controller: PinnedPreviewWindowController) {
        if controller.isFollowing {
            // 恢复跟随：同一时刻只允许一个跟随窗，把旧的静默锁定
            if let previous = followWindow, previous !== controller {
                previous.setFollowing(false)
            }
            followWindow = controller
            selectionWatcher.forceNextUpdate()
            selectionWatcher.start()
        } else if followWindow === controller {
            followWindow = nil
            selectionWatcher.stop()
        }
        rebuildMenu()
    }

    private func forget(_ controller: PinnedPreviewWindowController) {
        windows.removeAll { $0 === controller }
        if followWindow === controller {
            followWindow = nil
            selectionWatcher.stop()
        }
        rebuildMenu()
    }

    @objc private func closeAllWindows() {
        for c in windows { c.window?.close() }
        windows.removeAll()
        followWindow = nil
        selectionWatcher.stop()
        rebuildMenu()
    }

    @objc private func openPreferences() {
        if preferences == nil {
            let pc = PreferencesWindowController()
            pc.onHotKeyChange = { [weak self] spec -> String? in
                guard let self else { return nil }
                if let status = self.hotKeyManager.register(spec) {
                    // 注册失败就退回原来的快捷键，不要让用户处于「没有热键」的状态
                    self.hotKeyManager.register(Settings.hotKey)
                    return HotKeyManager.describe(status)
                }
                // 注册成功才落盘
                Settings.hotKey = spec
                if let conflict = SystemHotKeyConflict.conflictName(for: spec) {
                    self.hotKeyProblem = "被系统「\(conflict)」占用，按下不会触发"
                    self.rebuildMenu()
                    return "⚠️ 已保存，但这个组合被系统「\(conflict)」占用，按下不会触发。请换一个。"
                }
                self.hotKeyProblem = nil
                self.rebuildMenu()
                return nil
            }
            preferences = pc
        }
        preferences?.present()
    }

    // MARK: - 轮询开销基准（调试用）

    /// 开一个跟随窗、激活 Finder，然后只让轮询空跑指定秒数，期间不做任何其他动作。
    /// 这样外部用 top 采样到的，才是轮询本身的开销。
    private func runPollBench(url: URL, seconds: Double) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[基准] 文件不存在：\(url.path)")
            return
        }
        let controller = makeWindow(url: url, following: true)
        followWindow = controller
        // 绕过「Finder 必须在前台」的门槛。否则测量结果取决于用户有没有碰机器 ——
        // 上一次 40 秒里 138 次轮询只有 20 次真正发出事件，数据直接作废。
        selectionWatcher.forcePolling = true
        selectionWatcher.start()
        rebuildMenu()

        FinderSelection.activateFinder()
        NSLog("[基准] 开始：跟随窗已开，forcePolling=true（无视前台门槛），"
              + "接下来 \(Int(seconds)) 秒纯轮询，不做任何其他动作")

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            // stop() 会把「有效轮询 N 次 / 因非前台跳过 M 次」打进日志，
            // 用来确认这段时间轮询到底有没有真的在发事件
            self?.selectionWatcher.stop()
            NSLog("[基准] 结束")
        }
    }

    // MARK: - 内存自测（调试用）

    private func logMemory(_ stage: String) {
        NSLog("[内存] \(stage)  footprint=\(MemoryReport.formatted())  窗口数=\(windows.count)")
    }

    /// 反复开关窗口若干轮，观察内存是否逐轮上涨。
    /// 判据：各轮「全部关闭后」的数字应当回落到同一水平；逐轮抬高就是泄漏。
    private func runMemoryTest(_ urls: [URL], rounds: Int) {
        guard !urls.isEmpty else {
            NSLog("[内存] 用法: --mem-test <文件1> <文件2> ...")
            return
        }
        logMemory("启动基线（无窗口）")

        var delay = 0.0
        for round in 1...rounds {
            let r = round
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                for url in urls { self.makeWindow(url: url, following: false) }
                self.rebuildMenu()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 3.0) { [weak self] in
                self?.logMemory("第\(r)轮 已开 \(urls.count) 个窗口")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 3.5) { [weak self] in
                self?.closeAllWindows()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 7.0) { [weak self] in
                self?.logMemory("第\(r)轮 全部关闭后")
            }
            delay += 8.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.logMemory("结束")
            NSLog("[内存] 判据：各轮「全部关闭后」若逐轮上涨 → 有泄漏")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
