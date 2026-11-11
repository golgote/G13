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
        assert(KeyAction.parse("ALT+SHIFT")?.keycode == 0x38)
        assert(KeyAction.parse("ALT+SHIFT")?.option == true)
        assert(KeyAction.parse("CMD+CTRL+ALT+SHIFT")?.command == true)
        assert(KeyAction.parse("F6+F8") == nil)
        var events: [RecordedEvent] = []
        let mapper = KeyMapper { code, down, flags in
            events.append(RecordedEvent(keycode: code, down: down, flags: flags))
        }
        mapper.hasAccessibility = true

        // Timed modifier holds release after their deadline and on teardown.
        var holdEvents: [RecordedEvent] = []
        let holdMapper = KeyMapper { code, down, flags in
            holdEvents.append(RecordedEvent(keycode: code, down: down, flags: flags))
        }
        holdMapper.hasAccessibility = true
        holdMapper.startTimedHold(source: "G8", shortcut: "ALT", durationMilliseconds: 100)
        assert(holdEvents.map(\.down) == [true])
        RunLoop.current.run(until: Date().addingTimeInterval(0.16))
        assert(holdEvents.map(\.down) == [true, false])
        holdEvents.removeAll()
        holdMapper.startTimedHold(source: "G8", shortcut: "ALT", durationMilliseconds: 500)
        holdMapper.releaseAllKeys()
        RunLoop.current.run(until: Date().addingTimeInterval(0.55))
        assert(holdEvents.map(\.down) == [true, false])
        var mouseEvents: [(CGEventType, CGMouseButton, Int64, CGEventFlags)] = []
        mapper.mouseEventSink = { type, button, count, flags in
            mouseEvents.append((type, button, count, flags))
        }
        mapper.performMouseAction(.leftClick)
        assert(mouseEvents.map { $0.0 } == [.leftMouseDown, .leftMouseUp])
        assert(mouseEvents.map { $0.1 } == [.left, .left])
        assert(mouseEvents.map { $0.2 } == [1, 1])
        mouseEvents.removeAll()
        mapper.performMouseAction(.leftClick, modifiers: [.shift, .command])
        assert(mouseEvents.count == 2)
        assert(mouseEvents.allSatisfy { $0.3.contains(.maskShift) && $0.3.contains(.maskCommand) })
        mouseEvents.removeAll()
        mapper.performMouseAction(.rightClick)
        assert(mouseEvents.map { $0.0 } == [.rightMouseDown, .rightMouseUp])
        assert(mouseEvents.map { $0.1 } == [.right, .right])
        assert(mouseEvents.map { $0.2 } == [1, 1])
        mouseEvents.removeAll()
        mapper.performMouseAction(.middleClick)
        assert(mouseEvents.map { $0.0 } == [.otherMouseDown, .otherMouseUp])
        assert(mouseEvents.map { $0.1 } == [.center, .center])
        assert(mouseEvents.map { $0.2 } == [1, 1])
        mouseEvents.removeAll()
        mapper.performMouseAction(.doubleClick)
        assert(mouseEvents.map { $0.0 } == [.leftMouseDown, .leftMouseUp,
                                            .leftMouseDown, .leftMouseUp])
        assert(mouseEvents.map { $0.1 } == [.left, .left, .left, .left])
        assert(mouseEvents.map { $0.2 } == [1, 1, 2, 2])
        mouseEvents.removeAll()
        mapper.handleKey(name: "G12", isPressed: true,
                         mapping: ["G12": KeyAction.parse("SHIFT")!])
        mapper.performMouseAction(.leftClick)
        mapper.performMouseAction(.rightClick)
        assert(mouseEvents.map { $0.0 } == [.leftMouseDown, .leftMouseUp,
                                            .rightMouseDown, .rightMouseUp])
        assert(mouseEvents.allSatisfy { $0.3.contains(.maskShift) })
        mapper.handleKey(name: "G12", isPressed: false, mapping: [:])
        mouseEvents.removeAll()
        mapper.handleKey(name: "G21", isPressed: true,
                         mapping: ["G21": KeyAction.parse("ALT")!])
        mapper.performMouseAction(.leftClick)
        mapper.performMouseAction(.rightClick)
        assert(mouseEvents.allSatisfy { $0.3.contains(.maskAlternate) && !$0.3.contains(.maskShift) })
        mapper.handleKey(name: "G12", isPressed: true,
                         mapping: ["G12": KeyAction.parse("SHIFT")!])
        mouseEvents.removeAll()
        mapper.performMouseAction(.leftClick)
        mapper.performMouseAction(.rightClick)
        assert(mouseEvents.allSatisfy { $0.3.contains(.maskAlternate) && $0.3.contains(.maskShift) })
        mapper.handleKey(name: "G21", isPressed: false, mapping: [:])
        mapper.handleKey(name: "G12", isPressed: false, mapping: [:])
        mouseEvents.removeAll()
        mapper.handleKey(name: "G7", isPressed: true,
                         mapping: ["G7": KeyAction.parse("ALT+SHIFT")!])
        mapper.performMouseAction(.leftClick)
        mapper.performMouseAction(.rightClick)
        assert(mouseEvents.allSatisfy { $0.3.contains(.maskAlternate) && $0.3.contains(.maskShift) })
        mapper.handleKey(name: "G12", isPressed: true,
                         mapping: ["G12": KeyAction.parse("SHIFT")!])
        mapper.handleKey(name: "G7", isPressed: false, mapping: [:])
        mouseEvents.removeAll()
        mapper.performMouseAction(.leftClick)
        assert(mouseEvents.allSatisfy { $0.3.contains(.maskShift) && !$0.3.contains(.maskAlternate) })
        mapper.handleKey(name: "G12", isPressed: false, mapping: [:])
        mapper.startTimedHold(source: "G8", shortcut: "ALT+SHIFT", durationMilliseconds: 100)
        mouseEvents.removeAll()
        mapper.performMouseAction(.rightClick)
        assert(mouseEvents.allSatisfy { $0.3.contains(.maskShift) && $0.3.contains(.maskAlternate) })
        RunLoop.current.run(until: Date().addingTimeInterval(0.16))
        mouseEvents.removeAll()
        mapper.performMouseAction(.leftClick)
        assert(mouseEvents.allSatisfy { !$0.3.contains(.maskShift) })
        assert(mouseEvents.allSatisfy { !$0.3.contains(.maskAlternate) })
        events.removeAll()
        mapper.handleKey(name: "G7", isPressed: true,
                         mapping: ["G7": KeyAction.parse("ALT+SHIFT")!])
        mapper.releaseAllKeys()
        assert(events.filter(\.down).count == 2)
        assert(events.filter { !$0.down }.count == 2)
        assert(events.last?.flags.isEmpty == true)
        mapper.hasAccessibility = false
        mouseEvents.removeAll()
        mapper.performMouseAction(.leftClick)
        assert(mouseEvents.isEmpty)
        mapper.hasAccessibility = true
        events.removeAll()

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
