import Cocoa
import Carbon.HIToolbox

/// 为什么需要这个文件：
/// `RegisterEventHotKey` 对「已经被系统快捷键占用的组合」**依然返回 noErr**，
/// 但按键会被系统先截走，App 永远收不到 —— 表现就是「注册成功、按下去毫无反应」。
/// 所以光看 OSStatus 是检测不出冲突的，必须自己查一遍 com.apple.symbolichotkeys。
enum SystemHotKeyConflict {

    /// symbolichotkeys 里那些 id 对应的人话名字。查不到的就报 id。
    private static let names: [Int: String] = [
        7:  "移动聚焦到菜单栏",
        8:  "移动聚焦到 Dock",
        60: "选择上一个输入法",
        61: "选择输入菜单中的下一个输入源",
        64: "显示聚焦搜索 Spotlight",
        65: "聚焦搜索访达窗口",
        98: "显示帮助菜单",
    ]

    /// 返回占用同一组合的系统快捷键名字；没冲突返回 nil。
    static func conflictName(for spec: HotKeySpec) -> String? {
        guard let defaults = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
              let hotkeys = defaults.dictionary(forKey: "AppleSymbolicHotKeys")
        else { return nil }

        let wanted = cocoaModifierMask(fromCarbon: spec.carbonModifiers)

        for (key, raw) in hotkeys {
            guard let entry = raw as? [String: Any],
                  (entry["enabled"] as? Bool) == true,
                  let value = entry["value"] as? [String: Any],
                  let params = value["parameters"] as? [Int],
                  params.count >= 3
            else { continue }

            // parameters = [ASCII 字符, 虚拟键码, NSEvent 修饰键掩码]
            guard params[1] == Int(spec.keyCode), params[2] == wanted else { continue }

            let id = Int(key) ?? -1
            return names[id] ?? "系统快捷键 #\(id)"
        }
        return nil
    }

    /// Carbon 掩码 -> symbolichotkeys 里用的 NSEvent 掩码
    private static func cocoaModifierMask(fromCarbon m: UInt32) -> Int {
        var r = 0
        if m & UInt32(controlKey) != 0 { r |= 262_144 }   // NSEvent.ModifierFlags.control
        if m & UInt32(shiftKey)   != 0 { r |= 131_072 }   // .shift
        if m & UInt32(optionKey)  != 0 { r |= 524_288 }   // .option
        if m & UInt32(cmdKey)     != 0 { r |= 1_048_576 } // .command
        return r
    }
}
