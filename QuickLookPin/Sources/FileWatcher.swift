import Foundation

/// 盯住单个文件，**内容真的变了**才回调。
///
/// 两个坑，都踩过：
/// 1. 事件掩码里带 `.attrib` 会造成自我触发死循环 —— Quick Look 预览文件时系统和扩展
///    本身会去碰扩展属性/访问时间，于是 attrib 事件 → refreshPreviewItem() → 又碰属性
///    → 再次触发，预览窗口表现为持续闪烁。所以这里**不监听 .attrib**。
/// 2. 光靠事件本身不足以判断内容是否变化。收到事件后必须 stat 一次，
///    拿 (mtime, size, inode) 和上次比，一样就直接丢弃。这是止住闪烁的关键防线。
///
/// 编辑器的「原子保存」（写临时文件再 rename）会让旧 inode 失效，
/// 所以收到 .rename/.delete 之后要按路径重新 open。
final class FileWatcher {

    private struct Signature: Equatable {
        let mtime: TimeInterval
        let size: Int64
        let inode: UInt64
    }

    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounce: DispatchWorkItem?
    private var lastSignature: Signature?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        self.lastSignature = FileWatcher.signature(of: url)
        start()
    }

    deinit { stop() }

    // MARK: -

    private static func signature(of url: URL) -> Signature? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return Signature(
            mtime: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000,
            size: Int64(st.st_size),
            inode: UInt64(st.st_ino)
        )
    }

    private func start() {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[QuickLookPin] FileWatcher 打不开 \(url.lastPathComponent)")
            return
        }

        // 刻意不含 .attrib，见文件头注释
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        s.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let flags = source.data
            NSLog("[QuickLookPin] FileWatcher 收到事件 \(self.url.lastPathComponent) flags=\(flags.rawValue)")
            self.scheduleCheck()
            if flags.contains(.rename) || flags.contains(.delete) {
                self.restart()
            }
        }
        s.setCancelHandler { [fd] in
            if fd >= 0 { close(fd) }
        }
        source = s
        s.resume()
    }

    /// 合并短时间内的连续写入，然后再判断内容到底变没变
    private func scheduleCheck() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkAndFire() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// 止住闪烁的关键：内容签名没变就什么都不做
    private func checkAndFire() {
        let current = FileWatcher.signature(of: url)
        guard let current else { return }          // 文件暂时不在（原子保存中途），等下一次事件
        guard current != lastSignature else {
            NSLog("[QuickLookPin] FileWatcher \(url.lastPathComponent) 内容未变，忽略")
            return
        }
        lastSignature = current
        NSLog("[QuickLookPin] FileWatcher \(url.lastPathComponent) 内容已变，刷新预览")
        onChange()
    }

    private func restart() {
        stop()
        // 给编辑器一点时间把新文件落到原路径上
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, FileManager.default.fileExists(atPath: self.url.path) else { return }
            self.start()
            self.scheduleCheck()
        }
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        source?.cancel()   // cancelHandler 负责 close(fd)
        source = nil
        fd = -1
    }
}
