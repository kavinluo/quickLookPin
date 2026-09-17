import Cocoa
import Carbon.HIToolbox

/// 一个全局快捷键的描述。用 Carbon 语义存储：虚拟键码 + Carbon 修饰键掩码。
/// 之所以用 Carbon 而不是 NSEvent，是因为注册走 RegisterEventHotKey，它只认这套值。
struct HotKeySpec: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// 默认 ⌃Space
    static let defaultSpec = HotKeySpec(keyCode: UInt32(kVK_Space),
                                        carbonModifiers: UInt32(controlKey))

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + HotKeySpec.keyName(for: keyCode)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    // MARK: - 键码转可读名字

    static func keyName(for code: UInt32) -> String {
        if let special = specialKeyNames[Int(code)] { return special }
        if let ch = charForKeyCode(code), !ch.isEmpty { return ch.uppercased() }
        return "Key\(code)"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// 按当前键盘布局把虚拟键码翻成字符
    private static func charForKeyCode(_ code: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// 偏好存储。全部走 UserDefaults，没有配置文件，迁移无负担。
enum Settings {
    private static let d = UserDefaults.standard
    private static let kKeyCode  = "hotkey.keyCode"
    private static let kMods     = "hotkey.carbonModifiers"
    private static let kActivate = "pin.activateOnOpen"
    private static let kWatch    = "pin.watchFileChanges"

    static var hotKey: HotKeySpec {
        get {
            guard d.object(forKey: kKeyCode) != nil else { return .defaultSpec }
            return HotKeySpec(keyCode: UInt32(d.integer(forKey: kKeyCode)),
                              carbonModifiers: UInt32(d.integer(forKey: kMods)))
        }
        set {
            d.set(Int(newValue.keyCode), forKey: kKeyCode)
            d.set(Int(newValue.carbonModifiers), forKey: kMods)
        }
    }

    /// 固定窗口时是否把 App 激活。激活后才能直接滚动和按 ⌘W，代价是 Finder 短暂失焦。
    static var activateOnOpen: Bool {
        get { d.object(forKey: kActivate) == nil ? true : d.bool(forKey: kActivate) }
        set { d.set(newValue, forKey: kActivate) }
    }

    /// 文件被外部修改时自动刷新预览
    static var watchFileChanges: Bool {
        get { d.object(forKey: kWatch) == nil ? true : d.bool(forKey: kWatch) }
        set { d.set(newValue, forKey: kWatch) }
    }
}
