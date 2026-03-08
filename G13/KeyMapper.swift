// =============================================================
//  KeyMapper.swift
//  Key remapping from G13 keys to macOS via CGEvent
// =============================================================

import Foundation
import Combine
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
            default:                                 mainKey = part
            }
        }

        // Modifier alone (e.g. G15 mapped to "SHIFT")
        if mainKey == nil {
            if shift   { return KeyAction(keycode: 0x38, shift: false, control: false, option: false, command: false) }
            if control { return KeyAction(keycode: 0x3B, shift: false, control: false, option: false, command: false) }
            if option  { return KeyAction(keycode: 0x3A, shift: false, control: false, option: false, command: false) }
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

class KeyMapper: ObservableObject {

    @Published var hasAccessibility = false

    // Joystick direction state (to detect changes)
    // Joystick direction state (published so the UI can highlight active directions)
    @Published var joyUp = false
    @Published var joyDown = false
    @Published var joyLeft = false
    @Published var joyRight = false

    private static let modifierKeycodes: Set<UInt16> = [
        0x38, 0x3C, 0x3B, 0x3E, 0x3A, 0x3D, 0x37, 0x36, 0x39
    ]

    func checkAccessibility() {
        hasAccessibility = AXIsProcessTrusted()
        if !hasAccessibility {
            print("[KeyMapper] Accessibility permission required")
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    // Handle a G13 key press/release. If the key has no mapping, it is ignored.
    func handleKey(name: String, isPressed: Bool, mapping: [String: KeyAction]) {
        guard hasAccessibility else { return }
        guard let action = mapping[name] else { return }

        if KeyMapper.modifierKeycodes.contains(action.keycode)
            && !action.shift && !action.control && !action.option && !action.command {
            sendModifierEvent(keycode: action.keycode, keyDown: isPressed)
        } else {
            sendKeyEvent(action: action, keyDown: isPressed)
        }
    }

    // Handle joystick as configurable key directions.
    // Each direction (UP/DOWN/LEFT/RIGHT) can be mapped independently.
    // Diagonals are handled by combining two directions simultaneously.
    // If a direction has no mapping, it is ignored.
    func handleJoystickArrows(x: UInt8, y: UInt8, deadzone: Int, mapping: [String: KeyAction]) {
        guard hasAccessibility else { return }
        let center = 128

        let newUp    = Int(y) < (center - deadzone)
        let newDown  = Int(y) > (center + deadzone)
        let newLeft  = Int(x) < (center - deadzone)
        let newRight = Int(x) > (center + deadzone)

        if newUp != joyUp {
            joyUp = newUp
            if let action = mapping["UP"] { sendKeyEvent(action: action, keyDown: newUp) }
        }
        if newDown != joyDown {
            joyDown = newDown
            if let action = mapping["DOWN"] { sendKeyEvent(action: action, keyDown: newDown) }
        }
        if newLeft != joyLeft {
            joyLeft = newLeft
            if let action = mapping["LEFT"] { sendKeyEvent(action: action, keyDown: newLeft) }
        }
        if newRight != joyRight {
            joyRight = newRight
            if let action = mapping["RIGHT"] { sendKeyEvent(action: action, keyDown: newRight) }
        }
    }

    // MARK: - CGEvent injection

    private func sendKeyEvent(action: KeyAction, keyDown: Bool) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(action.keycode),
            keyDown: keyDown
        ) else { return }

        var flags: CGEventFlags = []
        if action.shift   { flags.insert(.maskShift) }
        if action.control { flags.insert(.maskControl) }
        if action.option  { flags.insert(.maskAlternate) }
        if action.command { flags.insert(.maskCommand) }
        if !flags.isEmpty { event.flags = flags }

        event.post(tap: .cghidEventTap)
    }

    private func sendModifierEvent(keycode: UInt16, keyDown: Bool) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keycode),
            keyDown: keyDown
        ) else { return }

        var flags: CGEventFlags = []
        if keyDown {
            switch keycode {
            case 0x38, 0x3C: flags = .maskShift
            case 0x3B, 0x3E: flags = .maskControl
            case 0x3A, 0x3D: flags = .maskAlternate
            case 0x37, 0x36: flags = .maskCommand
            default: break
            }
        }
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
        "MINUS": 0x1B, "EQUAL": 0x18,
        "LEFTBRACKET": 0x21, "RIGHTBRACKET": 0x1E,
        "BACKSLASH": 0x2A, "SEMICOLON": 0x29, "QUOTE": 0x27,
        "COMMA": 0x2B, "PERIOD": 0x2F, "DOT": 0x2F,
        "SLASH": 0x2C, "GRAVE": 0x32,
        "HOME": 0x73, "END": 0x77,
        "PAGEUP": 0x74, "PAGEDOWN": 0x79,
    ]
}
