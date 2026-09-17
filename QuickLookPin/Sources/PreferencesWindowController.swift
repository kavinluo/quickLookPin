import Cocoa
import Carbon.HIToolbox

/// 点一下开始录制，按下的第一个带修饰键的组合就是新快捷键。
final class KeyRecorderButton: NSButton {

    var onCapture: ((HotKeySpec) -> Void)?

    var spec: HotKeySpec = Settings.hotKey {
        didSet { refreshTitle() }
    }

    private var monitor: Any?
    private var recording = false {
        didSet { refreshTitle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    private func refreshTitle() {
        title = recording ? "请按下新快捷键…（Esc 取消）" : spec.displayString
    }

    @objc private func beginRecording() {
        guard !recording else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.endRecording()

            if event.keyCode == UInt16(kVK_Escape) { return nil }

            let mods = HotKeySpec.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else {
                // 不带修饰键的全局热键会吞掉普通打字，不允许
                NSSound.beep()
                return nil
            }
            let newSpec = HotKeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
            self.spec = newSpec
            self.onCapture?(newSpec)
            return nil
        }
    }

    private func endRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

final class PreferencesWindowController: NSWindowController {

    /// 返回 nil 表示注册成功，否则是给用户看的错误说明
    var onHotKeyChange: ((HotKeySpec) -> String?)?

    private var statusLabel: NSTextField!
    private var recorder: KeyRecorderButton!

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 230),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "QuickLookPin 偏好设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let hotkeyLabel = label("全局快捷键", bold: true)
        hotkeyLabel.frame = NSRect(x: 24, y: 178, width: 140, height: 18)
        content.addSubview(hotkeyLabel)

        recorder = KeyRecorderButton(frame: NSRect(x: 170, y: 172, width: 260, height: 28))
        recorder.onCapture = { [weak self] spec in
            guard let self else { return }
            // 落盘由 AppDelegate 在注册成功后负责，这里只负责显示结果
            if let problem = self.onHotKeyChange?(spec) {
                self.setStatus(problem, isError: true)
            } else {
                self.setStatus("已生效：\(spec.displayString)", isError: false)
            }
        }
        content.addSubview(recorder)

        let hint = label("提示：⌃Space 默认被系统的「切换输入法」占用。若注册失败，\n"
                         + "请到「系统设置 → 键盘 → 键盘快捷键 → 输入法」关掉它，或换一个组合。",
                         bold: false)
        hint.frame = NSRect(x: 24, y: 118, width: 410, height: 44)
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        content.addSubview(hint)

        let activate = NSButton(checkboxWithTitle: "固定时激活窗口（可立即滚动、按 ⌘W 关闭）",
                                target: self, action: #selector(toggleActivate(_:)))
        activate.frame = NSRect(x: 22, y: 88, width: 420, height: 20)
        activate.state = Settings.activateOnOpen ? .on : .off
        content.addSubview(activate)

        let watch = NSButton(checkboxWithTitle: "文件被外部修改时自动刷新预览",
                             target: self, action: #selector(toggleWatch(_:)))
        watch.frame = NSRect(x: 22, y: 62, width: 420, height: 20)
        watch.state = Settings.watchFileChanges ? .on : .off
        content.addSubview(watch)

        statusLabel = label("", bold: false)
        statusLabel.frame = NSRect(x: 24, y: 20, width: 410, height: 32)
        statusLabel.font = .systemFont(ofSize: 11)
        content.addSubview(statusLabel)
    }

    private func label(_ text: String, bold: Bool) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 12)
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 3
        return f
    }

    private func setStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    @objc private func toggleActivate(_ sender: NSButton) {
        Settings.activateOnOpen = (sender.state == .on)
    }

    @objc private func toggleWatch(_ sender: NSButton) {
        Settings.watchFileChanges = (sender.state == .on)
        setStatus("文件监视设置对之后新建的窗口生效。", isError: false)
    }

    func present() {
        recorder.spec = Settings.hotKey
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
