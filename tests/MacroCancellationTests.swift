import Foundation
import CoreGraphics

@main
struct MacroCancellationTests {
    @MainActor static func main() async {
        var events: [(UInt16, Bool)] = []
        let mapper = KeyMapper { code, down, _ in events.append((code, down)) }
        mapper.hasAccessibility = true

        mapper.playSequence(source: "G1", steps: ["A", "B"], delayMilliseconds: 1000)
        try? await Task.sleep(nanoseconds: 10_000_000)
        mapper.playSequence(source: "G1", steps: ["C", "D", "E"], delayMilliseconds: 100)
        let c = KeyAction.parse("C")!.keycode
        let d = KeyAction.parse("D")!.keycode
        for _ in 0..<100 where !events.contains(where: { $0.0 == c }) {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        assert(events.contains { $0.0 == c })
        try? await Task.sleep(nanoseconds: 10_000_000)
        assert(!events.contains { $0.0 == d })

        // The canceled predecessor must not discard the replacement task.
        mapper.releaseAllKeys()
        let countAtRelease = events.count
        try? await Task.sleep(nanoseconds: 240_000_000)
        assert(events.count == countAtRelease)
        print("Macro cancellation tests passed")
    }
}
