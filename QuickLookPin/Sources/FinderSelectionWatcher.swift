import Cocoa

/// 轮询 Finder 的当前选中项，变化时回调。
///
/// 为什么是轮询：Finder 没有提供「选中项发生变化」的公开通知，
/// AppleScript / Apple Event 都只能主动去问。想要事件驱动就得上
/// 辅助功能权限（AXObserver），那与本项目的既定技术路线冲突。
///
/// 开销控制：
/// - 只在确实存在「跟随模式」窗口时才 start()，平时完全不跑
/// - 只在 Finder 处于前台时才真正发 Apple Event，其余时刻直接跳过
/// - 路径列表没变就不回调，避免无谓刷新（这一条同时防住了预览刷新反过来
///   触发轮询的抖动）
final class FinderSelectionWatcher {

    private let interval: TimeInterval
    private let onChange: ([URL]) -> Void
    private var timer: Timer?
    private var lastPaths: [String] = []
    /// 连续失败计数，用于在权限被拒时自动停下来，不要每 0.4 秒弹一次错
    private var consecutiveFailures = 0
    /// 诊断用：因 Finder 不在前台而跳过的次数 / 真正发出 Apple Event 的次数
    private var skippedNotFrontmost = 0
    private var effectivePolls = 0

    /// **仅供 `--poll-bench` 基准测试使用**：无视「Finder 必须在前台」的门槛，无条件轮询。
    /// 正常功能路径不要打开 —— 会在用户用别的 App 时白白往 Finder 发 Apple Event。
    var forcePolling = false

    /// 权限被拒 / 持续失败时通知外部（外部负责提示用户并退出跟随模式）
    var onPersistentFailure: ((FinderSelectionError) -> Void)?

    init(interval: TimeInterval = 0.4, onChange: @escaping ([URL]) -> Void) {
        self.interval = interval
        self.onChange = onChange
    }

    deinit { stop() }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        // 用 .common 模式，保证在拖窗口 / 菜单弹出期间也照常轮询
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        t.tolerance = interval / 4
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSLog("[QuickLookPin] Finder 选中项轮询已启动（间隔 \(interval)s）")
        poll()
    }

    func stop() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        lastPaths = []
        consecutiveFailures = 0
        NSLog("[QuickLookPin] Finder 选中项轮询已停止（有效轮询 \(effectivePolls) 次，因非前台跳过 \(skippedNotFrontmost) 次）")
        skippedNotFrontmost = 0
        effectivePolls = 0
    }

    /// 让下一次轮询无条件回调一次（例如刚建好跟随窗口时）
    func forceNextUpdate() {
        lastPaths = []
    }

    private func poll() {
        // Finder 不在前台就不打扰它。
        // 这个 guard 是跟随模式失效的头号嫌疑，所以埋点记下来跳过了多少次、当时前台是谁。
        //
        // forcePolling 只给 --poll-bench 用：测「每次 Apple Event 往返的成本」时，
        // 这个门槛会让测量结果取决于「用户有没有碰机器」，根本测不稳。绕过它之后，
        // 测到的才是轮询本身的固定开销。正常功能路径永远不会打开这个开关。
        if !forcePolling,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.finder" {
            skippedNotFrontmost += 1
            if skippedNotFrontmost == 1 || skippedNotFrontmost % 25 == 0 {
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "未知"
                NSLog("[QuickLookPin] 轮询跳过：Finder 不在前台（累计 \(skippedNotFrontmost) 次，当前前台=\(front)）")
            }
            return
        }
        effectivePolls += 1

        switch FinderSelection.current() {
        case .failure(let error):
            consecutiveFailures += 1
            // 权限被拒的话再怎么轮询也没用，早点停
            if consecutiveFailures >= 3 {
                NSLog("[QuickLookPin] Finder 轮询连续失败 \(consecutiveFailures) 次，停止")
                stop()
                onPersistentFailure?(error)
            }

        case .success(let urls):
            consecutiveFailures = 0
            let paths = urls.map { $0.path }
            guard paths != lastPaths else { return }
            lastPaths = paths
            onChange(urls)
        }
    }
}
