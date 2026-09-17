import Foundation

enum FinderSelectionError: Error {
    /// 用户在「自动化」授权弹窗里点了拒绝，或系统设置里关掉了
    case notAuthorized(String)
    /// Finder 没在运行等其他脚本错误
    case scriptError(code: Int, message: String)

    var localizedMessage: String {
        switch self {
        case .notAuthorized(let m):
            return """
            无法读取 Finder 的选中项：自动化权限被拒绝。

            请到「系统设置 → 隐私与安全性 → 自动化」，
            找到 QuickLookPin，勾选 Finder。

            系统返回：\(m)
            """
        case .scriptError(let code, let message):
            return "读取 Finder 选中项失败（\(code)）：\(message)"
        }
    }
}

enum FinderSelection {

    /// 直接让 Finder 返回 POSIX 路径列表，省得在 Swift 这边解析 HFS 冒号路径
    private static let source = """
    tell application "Finder"
        set sel to selection as alias list
        set out to {}
        repeat with f in sel
            set end of out to POSIX path of (f as text)
        end repeat
        return out
    end tell
    """

    /// 预编译一次、全程复用。
    ///
    /// 跟随模式每 0.4 秒调一次 `current()`，而 `NSAppleScript(source:)` 每次构造都要
    /// **重新编译**脚本——编译远比执行贵。实测跟随模式开着时 CPU 占用 2~6%，
    /// 重复编译是主要来源。缓存之后只剩下执行和 Apple Event 往返的开销。
    ///
    /// NSAppleScript 不是线程安全的；本类型只在主线程调用，满足其要求。
    private static let compiledSelectionScript: NSAppleScript? = {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        if !script.compileAndReturnError(&errorInfo) {
            NSLog("[QuickLookPin] 选中项脚本预编译失败：\(errorInfo ?? [:])")
            return nil
        }
        return script
    }()

    /// 必须在主线程调用（NSAppleScript 的要求）
    static func current() -> Result<[URL], FinderSelectionError> {
        guard let script = compiledSelectionScript else {
            return .failure(.scriptError(code: -1, message: "AppleScript 编译失败"))
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "未知错误"
            // -1743: 用户未授权自动化；-600: 应用没在运行
            if code == -1743 {
                return .failure(.notAuthorized(message))
            }
            return .failure(.scriptError(code: code, message: message))
        }

        var urls: [URL] = []
        if descriptor.descriptorType == typeAEList {
            let n = descriptor.numberOfItems
            if n > 0 {
                for i in 1...n {
                    if let path = descriptor.atIndex(i)?.stringValue, !path.isEmpty {
                        urls.append(URL(fileURLWithPath: path))
                    }
                }
            }
        } else if let path = descriptor.stringValue, !path.isEmpty {
            urls.append(URL(fileURLWithPath: path))
        }
        return .success(urls)
    }

    // MARK: - 调试自测用
    //
    // 下面两个只给 --follow-test 用。它们会**改动** Finder 的状态（激活、开窗、改选中项），
    // 正常功能路径不会碰它们。

    /// 在 Finder 里新开一个窗口显示某个文件夹
    @discardableResult
    static func openFolder(_ url: URL) -> String? {
        run("""
        tell application "Finder"
            activate
            open folder (POSIX file "\(url.path)" as alias)
        end tell
        """)
    }

    /// 把 Finder 的选中项设成指定文件
    @discardableResult
    static func select(_ url: URL) -> String? {
        run("""
        tell application "Finder"
            activate
            set selection to {POSIX file "\(url.path)" as alias}
        end tell
        """)
    }

    /// 只把 Finder 拉到前台，不碰它的窗口和选中项
    @discardableResult
    static func activateFinder() -> String? {
        run("tell application \"Finder\" to activate")
    }

    /// 关掉 Finder 最前面的窗口
    @discardableResult
    static func closeFrontWindow() -> String? {
        run("""
        tell application "Finder"
            if (count of windows) > 0 then close front window
        end tell
        """)
    }

    /// 返回 nil 表示成功，否则是错误描述
    private static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return "AppleScript 编译失败" }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "未知错误"
            return "(\(code)) \(message)"
        }
        return nil
    }
}
