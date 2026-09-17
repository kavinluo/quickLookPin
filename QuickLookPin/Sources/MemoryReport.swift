import Foundation

/// 读自己进程的物理内存足迹。
/// 用 `phys_footprint`，口径和「活动监视器」的「内存」列一致 ——
/// 比 `ps` 的 RSS 更贴近系统实际按什么计费。
enum MemoryReport {

    /// 返回 MB；取不到返回 -1
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1024 / 1024
    }

    static func formatted() -> String {
        String(format: "%.1f MB", footprintMB())
    }
}
