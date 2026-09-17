import Cocoa
import Carbon.HIToolbox

/// 用 Carbon RegisterEventHotKey 注册全局快捷键。
/// 刻意不用 NSEvent.addGlobalMonitorForEvents —— 那个需要「辅助功能」权限。
/// Carbon 这条路不需要任何 TCC 权限，代价是 API 老旧。
final class HotKeyManager {

    /// 'QLPN'，用来区分是不是自己注册的热键
    private static let signature: OSType = 0x514C_504E

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
        installHandler()
    }

    deinit {
        unregister()
        if let h = eventHandler { RemoveEventHandler(h) }
    }

    // MARK: -

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            // 全程埋点：能走到这里就说明 Carbon 事件确实送达了本进程
            NSLog("[QuickLookPin] ★ Carbon 热键回调被调用")
            guard let event, let userData else {
                NSLog("[QuickLookPin] ★ event 或 userData 为空")
                return noErr
            }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hkID)
            guard err == noErr else {
                NSLog("[QuickLookPin] ★ GetEventParameter 失败 err=\(err)")
                return noErr
            }
            guard hkID.signature == HotKeyManager.signature else {
                NSLog("[QuickLookPin] ★ 签名不匹配 收到=\(hkID.signature) 期望=\(HotKeyManager.signature)")
                return noErr
            }
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            NSLog("[QuickLookPin] ★ 派发 onFire")
            DispatchQueue.main.async { mgr.onFire() }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)

        // 这一步以前没查返回值，是个真实疏漏：装不上处理器的话，
        // RegisterEventHotKey 依然返回成功，但回调永远不会被调用。
        if status == noErr {
            NSLog("[QuickLookPin] InstallEventHandler 成功")
        } else {
            NSLog("[QuickLookPin] ‼️ InstallEventHandler 失败 OSStatus=\(status) —— 热键永远不会触发")
        }
    }

    /// 注册成功返回 nil，失败返回 OSStatus。
    /// 最常见的失败是 -9878 (eventHotKeyExistsErr)：该组合已被系统或别的 App 占用。
    @discardableResult
    func register(_ spec: HotKeySpec) -> OSStatus? {
        unregister()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: HotKeyManager.signature, id: 1)
        let status = RegisterEventHotKey(spec.keyCode,
                                         spec.carbonModifiers,
                                         id,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return status }
        hotKeyRef = ref
        return nil
    }

    func unregister() {
        if let r = hotKeyRef {
            UnregisterEventHotKey(r)
            hotKeyRef = nil
        }
    }

    static func describe(_ status: OSStatus) -> String {
        switch status {
        case OSStatus(eventHotKeyExistsErr):
            return "该快捷键已被系统或其他 App 占用（OSStatus \(status)）"
        case OSStatus(eventHotKeyInvalidErr):
            return "快捷键组合无效（OSStatus \(status)）"
        default:
            return "注册失败（OSStatus \(status)）"
        }
    }
}
