import AppKit

@main
struct ShortcutCaptureTests {
    static func main() {
        func event(_ keycode: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                               modifierFlags: flags, timestamp: 0,
                                               windowNumber: 0, context: nil,
                                               characters: "", charactersIgnoringModifiers: "",
                                               isARepeat: false, keyCode: keycode) else {
                fatalError("Could not create test event")
            }
            return event
        }
        assert(G13ShortcutDecoder.shortcut(for: event(0x01)) == "S")
        assert(G13ShortcutDecoder.shortcut(for: event(0x01, [.command])) == "CMD+S")
        assert(G13ShortcutDecoder.shortcut(for: event(0x01, [.command, .control])) == "CMD+CTRL+S")
        assert(G13ShortcutDecoder.shortcut(for: event(0x0D, [.command, .option])) == "CMD+ALT+W")
        assert(G13ShortcutDecoder.shortcut(for: event(0x0D, [.command, .option, .shift])) == "CMD+ALT+SHIFT+W")
        assert(G13ShortcutDecoder.shortcut(for: event(0x21, [.command])) == "CMD+[")
        assert(G13ShortcutDecoder.shortcut(for: event(0x56)) == "NUMPAD3")
        assert(G13ShortcutDecoder.shortcut(for: event(0x45)) == "NUMPADPLUS")
        assert(G13ShortcutDecoder.shortcut(for: event(0x4E)) == "NUMPADMINUS")
        print("Shortcut capture tests passed")
    }
}
