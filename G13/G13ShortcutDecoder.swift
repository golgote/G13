import AppKit

enum G13ShortcutDecoder {
    static func shortcut(for event: NSEvent) -> String? {
        let key: String
        switch event.keyCode {
        case 0x56: key = "NUMPAD3"
        case 0x45: key = "NUMPADPLUS"
        case 0x4E: key = "NUMPADMINUS"
        case 0x21: key = "["
        case 0x1E: key = "]"
        default:
            guard let name = KeyMapper.macKeycodes.keys.sorted().first(where: {
                KeyMapper.macKeycodes[$0] == event.keyCode
            }) else { return nil }
            key = name
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if flags.contains(.command) { parts.append("CMD") }
        if flags.contains(.control) { parts.append("CTRL") }
        if flags.contains(.option) { parts.append("ALT") }
        if flags.contains(.shift) { parts.append("SHIFT") }
        parts.append(key)
        let shortcut = parts.joined(separator: "+")
        return KeyAction.parse(shortcut) == nil ? nil : shortcut
    }
}
