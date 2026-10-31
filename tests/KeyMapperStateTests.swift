import Foundation
import CoreGraphics

private struct RecordedEvent: Equatable {
    let keycode: UInt16
    let down: Bool
    let flags: CGEventFlags
}

@main
struct KeyMapperTests {
    static func main() {
        assert(KeyAction.parse("CMD+S")?.command == true)
        assert(KeyAction.parse("CMD+[")?.keycode == 0x21)
        assert(KeyAction.parse("CMD+]")?.keycode == 0x1E)
        assert(KeyAction.parse("NUMPAD3")?.keycode == 0x56)
        assert(KeyAction.parse("NUMPADPLUS")?.keycode == 0x45)
        assert(KeyAction.parse("NUMPADMINUS")?.keycode == 0x4E)
        assert(KeyAction.parse("CTRL+SHIFT+EQUAL")?.keycode == 0x18)
        assert(KeyAction.parse("CTRL+SHIFT+DOWN")?.keycode == 0x7D)
        assert(KeyAction.parse("F6+F8") == nil)
        var events: [RecordedEvent] = []
        let mapper = KeyMapper { code, down, flags in
            events.append(RecordedEvent(keycode: code, down: down, flags: flags))
        }
        mapper.hasAccessibility = true

        let w = KeyAction.parse("W")!
        let d = KeyAction.parse("D")!
        let s = KeyAction.parse("S")!
        let shift = KeyAction.parse("SHIFT")!
        let control = KeyAction.parse("CTRL")!

        // A profile change releases the original output, even if the mapping changes.
        mapper.handleKey(name: "G1", isPressed: true, mapping: ["G1": w])
        mapper.releaseAllKeys()
        mapper.handleKey(name: "G1", isPressed: false, mapping: ["G1": s])
        assert(events == [RecordedEvent(keycode: w.keycode, down: true, flags: []),
                          RecordedEvent(keycode: w.keycode, down: false, flags: [])])

        events.removeAll()
        mapper.handleKey(name: "G1", isPressed: true, mapping: ["G1": w])
        mapper.handleKey(name: "G2", isPressed: true, mapping: ["G2": w])
        mapper.handleKey(name: "G1", isPressed: false, mapping: [:])
        assert(events.count == 1)
        mapper.handleKey(name: "G2", isPressed: false, mapping: [:])
        assert(events.map(\.down) == [true, false])

        // Shared keycodes with different modifiers must transition cleanly.
        events.removeAll()
        let commandS = KeyAction.parse("CMD+S")!
        mapper.handleKey(name: "G1", isPressed: true, mapping: ["G1": s])
        mapper.handleKey(name: "G2", isPressed: true, mapping: ["G2": commandS])
        mapper.handleKey(name: "G2", isPressed: false, mapping: [:])
        mapper.handleKey(name: "G1", isPressed: false, mapping: [:])
        assert(events.map(\.down) == [true, false, true, false, true, false])
        assert(events[2].flags.contains(.maskCommand))
        assert(!events[4].flags.contains(.maskCommand))

        events.removeAll()
        mapper.handleKey(name: "G15", isPressed: true, mapping: ["G15": shift])
        mapper.handleKey(name: "G20", isPressed: true, mapping: ["G20": control])
        mapper.handleKey(name: "G15", isPressed: false, mapping: [:])
        mapper.handleKey(name: "G20", isPressed: false, mapping: [:])
        assert(events.count == 4)
        assert(events[0].flags.contains(.maskShift))
        assert(events[1].flags.contains(.maskShift) && events[1].flags.contains(.maskControl))
        assert(!events[2].flags.contains(.maskShift) && events[2].flags.contains(.maskControl))
        assert(events[3].flags.isEmpty)

        events.removeAll()
        mapper.handleJoystickArrows(x: 255, y: 0, deadzone: 20,
                                    mapping: ["UP": w, "RIGHT": d])
        assert(events.filter(\.down).count == 2)
        mapper.releaseAllKeys()
        assert(events.filter { !$0.down }.count == 2)
        assert(!mapper.joyUp && !mapper.joyRight)
        mapper.releaseAllKeys()
        assert(events.count == 4)

        events.removeAll()
        mapper.handleJoystickArrows(x: 255, y: 0, deadzone: 20,
                                    mapping: ["UP": w, "RIGHT": d],
                                    vertical: false, horizontal: true)
        assert(events.filter(\.down).map(\.keycode) == [d.keycode])
        mapper.handleJoystickArrows(x: 255, y: 0, deadzone: 20,
                                    mapping: ["UP": w, "RIGHT": d],
                                    vertical: true, horizontal: false)
        assert(events.filter { !$0.down }.map(\.keycode) == [d.keycode])
        assert(events.filter(\.down).map(\.keycode) == [d.keycode, w.keycode])
        mapper.releaseAllKeys()

        assert(KeyMapper.scrollAmount(axis: 10, deadzone: 20, speed: 2) == 0)
        assert(KeyMapper.scrollAmount(axis: 100, deadzone: 20, speed: 2) > 0)
        assert(KeyMapper.scrollAmount(axis: -100, deadzone: 20, speed: 2) < 0)
        var scrollEvents: [(Int32, Int32)] = []
        mapper.scrollSink = { vertical, horizontal in
            scrollEvents.append((vertical, horizontal))
        }
        mapper.handleJoystickScroll(x: 200, y: 20, deadzone: 20,
                                    verticalSpeed: 1, horizontalSpeed: 5,
                                    vertical: true, horizontal: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        assert(!scrollEvents.isEmpty)
        assert(scrollEvents.allSatisfy { $0.0 == 1 && $0.1 > $0.0 })
        scrollEvents.removeAll()
        mapper.handleJoystickScroll(x: 200, y: 20, deadzone: 20,
                                    verticalSpeed: 1, horizontalSpeed: 5,
                                    vertical: false, horizontal: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        assert(!scrollEvents.isEmpty && scrollEvents.allSatisfy { $0.0 == 0 && $0.1 > 0 })
        scrollEvents.removeAll()
        mapper.handleJoystickScroll(x: 200, y: 20, deadzone: 20,
                                    verticalSpeed: 1, horizontalSpeed: 5,
                                    vertical: true, horizontal: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        assert(!scrollEvents.isEmpty && scrollEvents.allSatisfy { $0.0 > 0 && $0.1 == 0 })
        mapper.releaseAllKeys()
        let stoppedAt = scrollEvents.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        assert(scrollEvents.count == stoppedAt)

        print("KeyMapper state tests passed")
    }
}
