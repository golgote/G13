import Foundation
import Darwin

// Read-only host counters for the optional LCD status page. Values are
// approximate and need no Accessibility, Screen Recording, or root access.
struct G13SystemSnapshot {
    let cpuPercent: Int?
    let usedMemoryGiB: Double?
    let totalMemoryGiB: Double
}

final class G13SystemMonitor {
    private var previousTicks: (total: UInt64, idle: UInt64)?

    func sample() -> G13SystemSnapshot {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let gib = 1_073_741_824.0
        return G13SystemSnapshot(cpuPercent: sampleCPU(),
                                 usedMemoryGiB: sampleMemory(totalBytes: totalBytes).map { Double($0) / gib },
                                 totalMemoryGiB: Double(totalBytes) / gib)
    }

    private func sampleCPU() -> Int? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size /
                                            MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let idle = UInt64(info.cpu_ticks.2)
        let total = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.1) +
                    idle + UInt64(info.cpu_ticks.3)
        defer { previousTicks = (total, idle) }
        guard let previous = previousTicks, total > previous.total,
              idle >= previous.idle else { return nil }
        let elapsed = total - previous.total
        let busy = elapsed - min(elapsed, idle - previous.idle)
        return min(100, Int((busy * 100) / elapsed))
    }

    private func sampleMemory(totalBytes: UInt64) -> UInt64? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size /
                                            MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let reclaimable = (UInt64(info.free_count) + UInt64(info.inactive_count)) *
                          UInt64(getpagesize())
        return totalBytes - min(totalBytes, reclaimable)
    }
}
