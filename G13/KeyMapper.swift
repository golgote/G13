// =============================================================
//  KeyMapper.swift
//  Key remapping from G13 keys to macOS via CGEvent
// =============================================================

import Foundation
import Combine
import AppKit
import CoreGraphics
import ApplicationServices

// MARK: - KeyAction

// Represents a keyboard action: a main key plus optional modifiers.
// Parses strings like "W", "SHIFT", "CMD+C", "CTRL+SHIFT+S".
struct KeyAction: Codable, Equatable {
    let keycode: UInt16
    let shift: Bool
    let control: Bool
    let option: Bool
    let command: Bool

    static func parse(_ string: String) -> KeyAction? {
        let parts = string.uppercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var shift = false, control = false, option = false, command = false
        var mainKey: String? = nil

        for part in parts {
            switch part {
            case "SHIFT", "LEFTSHIFT", "RIGHTSHIFT": shift = true
            case "CTRL", "CONTROL":                  control = true
            case "ALT", "OPTION":                    option = true
            case "CMD", "COMMAND":                   command = true
            default:
                guard mainKey == nil else { return nil }
                mainKey = part
            }
        }

        // A key can hold one or several modifiers without a main key.
        // The keycode is the first modifier; remaining flags are expanded
        // into separately owned modifier key-downs by KeyMapper.
        if mainKey == nil {
            if shift   { return KeyAction(keycode: 0x38, shift: false, control: control, option: option, command: command) }
            if control { return KeyAction(keycode: 0x3B, shift: false, control: false, option: option, command: command) }
            if option  { return KeyAction(keycode: 0x3A, shift: false, control: false, option: false, command: command) }
            if command { return KeyAction(keycode: 0x37, shift: false, control: false, option: false, command: false) }
            return nil
        }

        guard let keycode = KeyMapper.macKeycodes[mainKey!] else {
            print("[KeyMapper] Unknown key: '\(mainKey!)'")
            return nil
        }

        return KeyAction(keycode: keycode, shift: shift, control: control, option: option, command: command)
    }

    // Human-readable name (e.g. "CMD+S", "SHIFT", "W")
    var displayName: String {
        let keyName = KeyMapper.macKeycodes.first(where: { $0.value == keycode })?.key ?? "?"
        var parts: [String] = []
        if command { parts.append("CMD") }
        if control { parts.append("CTRL") }
        if option  { parts.append("ALT") }
        if shift   { parts.append("SHIFT") }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }
}

// MARK: - KeyMapper

enum G13MouseAction: String, Codable, CaseIterable {
    case leftClick, rightClick, middleClick, doubleClick

    var label: String {
        switch self {
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .doubleClick: return "Double Click"
        }
    }
}

enum G13MouseModifier: String, Codable, CaseIterable, Hashable {
    case shift, control, option, command

    var label: String {
        switch self {
        case .shift: return "Shift"
        case .control: return "Control"
        case .option: return "Option"
        case .command: return "Command"
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .command: return .maskCommand
        }
    }
}

class KeyMapper: ObservableObject {

    @Published var hasAccessibility = false

    // Joystick direction state (to detect changes)
    // Joystick direction state (published so the UI can highlight active directions)
    @Published var joyUp = false
    @Published var joyDown = false
    @Published var joyLeft = false
    @Published var joyRight = false

    private static let modifierKeycodes: Set<UInt16> = [
        0x38, 0x3C, 0x3B, 0x3E, 0x3A, 0x3D, 0x37, 0x36
    ]

    private var accessibilityTimer: Timer?
    private var terminationObserver: NSObjectProtocol?
    // Keep the action from key-down so changes to a profile cannot change its key-up.
    private var pressedSources: [String: KeyAction] = [:]
    // The most recently pressed source owns a shared macOS keycode. Switching
    // owners sends a balanced key-up/key-down pair, including changed modifiers.
    private var pressedOrder: [String] = []
    private var sequenceTasks: [String: Task<Void, Never>] = [:]
    private var sequenceTokens: [String: UUID] = [:]
    private var timedHoldTimers: [String: Timer] = [:]
    private var timedHoldActions: [String: KeyAction] = [:]
    private var scrollTimer: Timer?
    private var scrollX: UInt8 = 128
    private var scrollY: UInt8 = 128
    private var scrollDeadzone = 20
    private var verticalScrollSpeed = 2
    private var horizontalScrollSpeed = 2
    private var scrollVertical = true
    private var scrollHorizontal = false
    var scrollSink: ((Int32, Int32) -> Void)?
    // Receives generated events in tests without posting them to the system.
    var mouseEventSink: ((CGEventType, CGMouseButton, Int64, CGEventFlags) -> Void)?
    private let eventSink: ((UInt16, Bool, CGEventFlags) -> Void)?

    init(eventSink: ((UInt16, Bool, CGEventFlags) -> Void)? = nil) {
        self.eventSink = eventSink
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.releaseAllKeys()
        }
    }

    deinit {
        accessibilityTimer?.invalidate()
        scrollTimer?.invalidate()
        for timer in timedHoldTimers.values { timer.invalidate() }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func checkAccessibility(prompt: Bool = false) {
        let trusted = AXIsProcessTrusted()
        if !trusted && hasAccessibility { releaseAllKeys() }
        hasAccessibility = trusted
        if !trusted && prompt {
            print("[KeyMapper] Accessibility permission required")
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        startAccessibilityPolling()
    }

    func startAccessibilityPolling() {
        guard accessibilityTimer == nil else { return }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.hasAccessibility {
                if !trusted { self.releaseAllKeys() }
                self.hasAccessibility = trusted
                print("[KeyMapper] Accessibility permission \(trusted ? "granted" : "revoked")")
            }
        }
    }

    // Handle a G13 key press/release. If the key has no mapping, it is ignored.
    func handleKey(name: String, isPressed: Bool, mapping: [String: KeyAction]) {
        guard !isPressed || hasAccessibility else { return }
        updateMappedSource("key:\(name)", isPressed: isPressed, action: mapping[name])
    }

    // Handle joystick as configurable key directions.
    // Each direction (UP/DOWN/LEFT/RIGHT) can be mapped independently.
    // Diagonals are handled by combining two directions simultaneously.
    // If a direction has no mapping, it is ignored.
    func handleJoystickArrows(x: UInt8, y: UInt8, deadzone: Int, mapping: [String: KeyAction],
                              vertical: Bool = true, horizontal: Bool = true) {
        guard hasAccessibility else { return }
        let center = 128

        let newUp    = vertical && Int(y) < (center - deadzone)
        let newDown  = vertical && Int(y) > (center + deadzone)
        let newLeft  = horizontal && Int(x) < (center - deadzone)
        let newRight = horizontal && Int(x) > (center + deadzone)

        if newUp != joyUp {
            joyUp = newUp
            updateSource("joy:UP", isPressed: newUp, action: mapping["UP"])
        }
        if newDown != joyDown {
            joyDown = newDown
            updateSource("joy:DOWN", isPressed: newDown, action: mapping["DOWN"])
        }
        if newLeft != joyLeft {
            joyLeft = newLeft
            updateSource("joy:LEFT", isPressed: newLeft, action: mapping["LEFT"])
        }
        if newRight != joyRight {
            joyRight = newRight
            updateSource("joy:RIGHT", isPressed: newRight, action: mapping["RIGHT"])
        }
    }

    // Hold the stick to scroll continuously. Centering it or releasing all
    // input stops the timer, including on disconnect and profile changes.
    func handleJoystickScroll(x: UInt8, y: UInt8, deadzone: Int,
                              verticalSpeed: Int, horizontalSpeed: Int,
                              vertical: Bool, horizontal: Bool) {
        guard hasAccessibility else { stopScroll(); return }
        scrollX = x
        scrollY = y
        scrollDeadzone = min(max(deadzone, 0), 127)
        verticalScrollSpeed = min(max(verticalSpeed, 1), 5)
        horizontalScrollSpeed = min(max(horizontalSpeed, 1), 5)
        scrollVertical = vertical
        scrollHorizontal = horizontal
        let upDown = vertical ? Self.scrollAmount(axis: 128 - Int(y),
                                                  deadzone: scrollDeadzone, speed: verticalScrollSpeed) : 0
        let side = horizontal ? Self.scrollAmount(axis: Int(x) - 128,
                                                  deadzone: scrollDeadzone, speed: horizontalScrollSpeed) : 0
        if upDown == 0 && side == 0 {
            stopScroll()
        } else if scrollTimer == nil {
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.scrollTick()
            }
        }
    }

    static func scrollAmount(axis: Int, deadzone: Int, speed: Int) -> Int32 {
        let excess = abs(axis) - min(max(deadzone, 0), 127)
        guard excess > 0 else { return 0 }
        let lines = min(4, 1 + excess * (min(max(speed, 1), 5) - 1) / 160)
        return Int32(axis > 0 ? lines : -lines)
    }

    private func scrollTick() {
        guard hasAccessibility else { stopScroll(); return }
        let vertical = scrollVertical ? Self.scrollAmount(axis: 128 - Int(scrollY),
                                                          deadzone: scrollDeadzone, speed: verticalScrollSpeed) : 0
        let side = scrollHorizontal ? Self.scrollAmount(axis: Int(scrollX) - 128,
                                                        deadzone: scrollDeadzone, speed: horizontalScrollSpeed) : 0
        guard vertical != 0 || side != 0 else { stopScroll(); return }
        if let scrollSink {
            scrollSink(vertical, side)
        } else if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                     wheelCount: 2, wheel1: vertical,
                                     wheel2: side, wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func stopScroll() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        scrollX = 128
        scrollY = 128
    }

    // Release ordinary keys before modifiers so shortcuts cannot linger after
    // disconnects, profile edits, permission changes, or normal termination.
    func releaseAllKeys() {
        stopScroll()
        for timer in timedHoldTimers.values { timer.invalidate() }
        timedHoldTimers.removeAll()
        timedHoldActions.removeAll()
        for task in sequenceTasks.values { task.cancel() }
        sequenceTasks.removeAll()
        sequenceTokens.removeAll()
        let active = Set(pressedSources.values.map(\.keycode))
            .compactMap { activeAction(for: $0) }
            .sorted { lhs, rhs in
                let lhsModifier = isStandaloneModifier(lhs)
                let rhsModifier = isStandaloneModifier(rhs)
                return lhsModifier == rhsModifier ? lhs.keycode < rhs.keycode : !lhsModifier
            }
        for action in active {
            pressedSources = pressedSources.filter { $0.value.keycode != action.keycode }
            pressedOrder.removeAll { source in pressedSources[source] == nil }
            post(action: action, keyDown: false)
        }
        pressedSources.removeAll()
        pressedOrder.removeAll()
        joyUp = false
        joyDown = false
        joyLeft = false
        joyRight = false
    }

    // A timed hold outlives the physical G13 key-up. Repeated presses restart
    // its timer, while releaseAllKeys always balances the synthetic key-down.
    func startTimedHold(source: String, shortcut: String, durationMilliseconds: Int) {
        guard hasAccessibility, (100...30_000).contains(durationMilliseconds),
              let action = KeyAction.parse(shortcut) else { return }
        let ownership = "timed:\(source)"
        timedHoldTimers[ownership]?.invalidate()
        if let previous = timedHoldActions[ownership], previous != action {
            updateMappedSource(ownership, isPressed: false, action: nil)
            timedHoldActions.removeValue(forKey: ownership)
        }
        if timedHoldActions[ownership] == nil {
            updateMappedSource(ownership, isPressed: true, action: action)
            timedHoldActions[ownership] = action
        }
        timedHoldTimers[ownership] = Timer.scheduledTimer(withTimeInterval: Double(durationMilliseconds) / 1000,
                                                          repeats: false) { [weak self] _ in
            self?.timedHoldTimers.removeValue(forKey: ownership)
            self?.timedHoldActions.removeValue(forKey: ownership)
            self?.updateMappedSource(ownership, isPressed: false, action: nil)
        }
    }

    // A sequence is a finite series of key taps. Cancellation occurs on profile
    // changes, disconnects, permission loss, and termination.
    func playSequence(source: String, steps: [String], delayMilliseconds: Int) {
        guard hasAccessibility, !steps.isEmpty, steps.count <= 16,
              steps.allSatisfy({ KeyAction.parse($0) != nil }) else { return }
        sequenceTasks[source]?.cancel()
        let token = UUID()
        sequenceTokens[source] = token
        let delay = UInt64(min(max(delayMilliseconds, 25), 1000)) * 1_000_000
        sequenceTasks[source] = Task { @MainActor [weak self] in
            for (index, step) in steps.enumerated() {
                guard !Task.isCancelled, let self, let action = KeyAction.parse(step) else { break }
                if self.isModifierChord(action) {
                    let stepSource = "sequence:\(source):\(token):\(index)"
                    self.updateMappedSource(stepSource, isPressed: true, action: action)
                    self.updateMappedSource(stepSource, isPressed: false, action: nil)
                } else {
                    self.post(action: action, keyDown: true)
                    self.post(action: action, keyDown: false)
                }
                try? await Task.sleep(nanoseconds: delay)
            }
            // A canceled predecessor must never remove its replacement task.
            if self?.sequenceTokens[source] == token {
                self?.sequenceTasks.removeValue(forKey: source)
                self?.sequenceTokens.removeValue(forKey: source)
            }
        }
    }

    private func activeAction(for keycode: UInt16) -> KeyAction? {
        for source in pressedOrder.reversed() {
            if let action = pressedSources[source], action.keycode == keycode { return action }
        }
        return nil
    }

    private func isModifierChord(_ action: KeyAction) -> Bool {
        Self.modifierKeycodes.contains(action.keycode) &&
            (action.shift || action.control || action.option || action.command)
    }

    // A chord such as ALT+SHIFT owns two independent modifier keys. Releasing
    // either this source or another source holding the same key stays balanced.
    private func updateMappedSource(_ source: String, isPressed: Bool, action: KeyAction?) {
        if !isPressed {
            updateSource(source, isPressed: false, action: nil)
            for code in [UInt16(0x38), 0x3B, 0x3A, 0x37] {
                updateSource("\(source):modifier:\(code)", isPressed: false, action: nil)
            }
            return
        }
        guard let action else { return }
        guard isModifierChord(action) else {
            updateSource(source, isPressed: true, action: action)
            return
        }
        var codes: [UInt16] = [action.keycode]
        if action.shift { codes.append(0x38) }
        if action.control { codes.append(0x3B) }
        if action.option { codes.append(0x3A) }
        if action.command { codes.append(0x37) }
        for code in codes {
            let modifier = KeyAction(keycode: code, shift: false, control: false,
                                     option: false, command: false)
            updateSource("\(source):modifier:\(code)", isPressed: true, action: modifier)
        }
    }

    private func updateSource(_ source: String, isPressed: Bool, action: KeyAction?) {
        if isPressed {
            guard let action, pressedSources[source] == nil else { return }
            let previous = activeAction(for: action.keycode)
            pressedSources[source] = action
            pressedOrder.append(source)
            if previous != action {
                if let previous { post(action: previous, keyDown: false) }
                post(action: action, keyDown: true)
            }
        } else {
            guard let heldAction = pressedSources[source] else { return }
            let previous = activeAction(for: heldAction.keycode)
            pressedSources.removeValue(forKey: source)
            pressedOrder.removeAll { $0 == source }
            let replacement = activeAction(for: heldAction.keycode)
            if previous != replacement {
                if let previous { post(action: previous, keyDown: false) }
                if let replacement { post(action: replacement, keyDown: true) }
            }
        }
    }

    private func isStandaloneModifier(_ action: KeyAction) -> Bool {
        Self.modifierKeycodes.contains(action.keycode)
            && !action.shift && !action.control && !action.option && !action.command
    }

    private func post(action: KeyAction, keyDown: Bool) {
        if isStandaloneModifier(action) {
            sendModifierEvent(keycode: action.keycode, keyDown: keyDown)
        } else {
            sendKeyEvent(action: action, keyDown: keyDown)
        }
    }

    private func activeStandaloneModifierFlags() -> CGEventFlags {
        var flags: CGEventFlags = []
        for action in pressedSources.values where isStandaloneModifier(action) {
            switch action.keycode {
            case 0x38, 0x3C: flags.insert(.maskShift)
            case 0x3B, 0x3E: flags.insert(.maskControl)
            case 0x3A, 0x3D: flags.insert(.maskAlternate)
            case 0x37, 0x36: flags.insert(.maskCommand)
            default: break
            }
        }
        return flags
    }

    // MARK: - CGEvent injection

    func performMouseAction(_ action: G13MouseAction, modifiers: [G13MouseModifier] = []) {
        guard hasAccessibility else { return }
        guard let location = CGEvent(source: nil)?.location else { return }
        var modifierFlags = activeStandaloneModifierFlags()
        for modifier in modifiers { modifierFlags.insert(modifier.eventFlag) }
        let button: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType
        switch action {
        case .leftClick, .doubleClick:
            button = .left
            downType = .leftMouseDown
            upType = .leftMouseUp
        case .rightClick:
            button = .right
            downType = .rightMouseDown
            upType = .rightMouseUp
        case .middleClick:
            button = .center
            downType = .otherMouseDown
            upType = .otherMouseUp
        }
        let clickCount = action == .doubleClick ? 2 : 1
        for count in 1...clickCount {
            if let mouseEventSink {
                mouseEventSink(downType, button, Int64(count), modifierFlags)
                mouseEventSink(upType, button, Int64(count), modifierFlags)
                continue
            }
            guard let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                                     mouseCursorPosition: location, mouseButton: button),
                  let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                                   mouseCursorPosition: location, mouseButton: button) else { return }
            down.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            down.flags = down.flags.union(modifierFlags)
            up.flags = up.flags.union(modifierFlags)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private func sendKeyEvent(action: KeyAction, keyDown: Bool) {
        var flags = activeStandaloneModifierFlags()
        if action.shift   { flags.insert(.maskShift) }
        if action.control { flags.insert(.maskControl) }
        if action.option  { flags.insert(.maskAlternate) }
        if action.command { flags.insert(.maskCommand) }
        if let eventSink {
            eventSink(action.keycode, keyDown, flags)
            return
        }

        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(action.keycode),
            keyDown: keyDown
        ) else { return }
        event.flags = flags

        event.post(tap: .cghidEventTap)
    }

    private func sendModifierEvent(keycode: UInt16, keyDown: Bool) {
        let flags = activeStandaloneModifierFlags()
        if let eventSink {
            eventSink(keycode, keyDown, flags)
            return
        }

        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keycode),
            keyDown: keyDown
        ) else { return }

        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    // MARK: - macOS keycodes

    static let macKeycodes: [String: UInt16] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04,
        "G": 0x05, "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09,
        "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F,
        "Y": 0x10, "T": 0x11, "U": 0x20, "I": 0x22, "O": 0x1F,
        "P": 0x23, "L": 0x25, "J": 0x26, "K": 0x28, "N": 0x2D,
        "M": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        "ESCAPE": 0x35, "ESC": 0x35, "TAB": 0x30, "SPACE": 0x31,
        "RETURN": 0x24, "ENTER": 0x24,
        "DELETE": 0x33, "BACKSPACE": 0x33, "FORWARDDELETE": 0x75,
        "SHIFT": 0x38, "LEFTSHIFT": 0x38, "RIGHTSHIFT": 0x3C,
        "CONTROL": 0x3B, "CTRL": 0x3B,
        "OPTION": 0x3A, "ALT": 0x3A,
        "COMMAND": 0x37, "CMD": 0x37,
        "CAPSLOCK": 0x39,
        "UP": 0x7E, "DOWN": 0x7D, "LEFT_ARROW": 0x7B, "RIGHT_ARROW": 0x7C,
        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76,
        "F5": 0x60, "F6": 0x61, "F7": 0x62, "F8": 0x64,
        "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
        "NUMPAD3": 0x56, "KP3": 0x56,
        "NUMPADPLUS": 0x45, "NUMPADMINUS": 0x4E,
        "MINUS": 0x1B, "EQUAL": 0x18,
        "LEFTBRACKET": 0x21, "RIGHTBRACKET": 0x1E,
        "[": 0x21, "]": 0x1E,
        "BACKSLASH": 0x2A, "SEMICOLON": 0x29, "QUOTE": 0x27,
        "COMMA": 0x2B, "PERIOD": 0x2F, "DOT": 0x2F,
        "SLASH": 0x2C, "GRAVE": 0x32,
        "HOME": 0x73, "END": 0x77,
        "PAGEUP": 0x74, "PAGEDOWN": 0x79,
    ]
}
