import Foundation

@main
struct SystemMonitorTests {
    static func main() {
        let monitor = G13SystemMonitor()
        _ = monitor.sample()
        Thread.sleep(forTimeInterval: 0.2)
        let snapshot = monitor.sample()
        assert(snapshot.totalMemoryGiB > 0)
        assert(snapshot.usedMemoryGiB != nil)
        assert(snapshot.usedMemoryGiB! >= 0 && snapshot.usedMemoryGiB! <= snapshot.totalMemoryGiB)
        assert(snapshot.cpuPercent != nil)
        assert((0...100).contains(snapshot.cpuPercent!))
        print("Read-only CPU and RAM sampling passed")
    }
}
