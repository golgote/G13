// =============================================================
//  ContentView.swift
//  Settings window with editable key mapping and profile management
// =============================================================

import SwiftUI

struct ContentView: View {
    @ObservedObject var device: G13Device
    @ObservedObject var keyMapper: KeyMapper
    @ObservedObject var profileManager: ProfileManager

    @State private var captureTarget: String? = nil
    @State private var captureIsJoystick: Bool = false
    @State private var statusMessage: String = ""
    @State private var showNewProfileSheet: Bool = false
    @State private var newProfileName: String = ""

    var body: some View {
        VStack(spacing: 12) {
            header
            Divider()
            profileBar
            Divider()

            HStack(alignment: .top, spacing: 16) {
                // Left column: key layout + joystick config
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("G13 Keys")
                            .font(.headline)
                        Text(captureHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        keyboardLayout
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        specialButtons
                    }
                    joystickConfig
                }

                // Right column
                VStack(spacing: 12) {
                    backlightControls
                    joystickLiveInfo
                    accessibilityStatus
                    Spacer()
                }
                .frame(width: 180)
            }

            Divider()

            HStack {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if captureTarget != nil {
                    Button("Cancel") {
                        captureTarget = nil
                        statusMessage = ""
                    }
                    .controlSize(.small)
                }
                Spacer()
                Button("Reset profile to defaults") {
                    profileManager.resetActiveProfile()
                    statusMessage = "Profile reset to defaults"
                }
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 680, height: 700)
        .background(KeyCaptureView(isCapturing: captureTarget != nil, onKeyCaptured: handleKeyCaptured))
        .sheet(isPresented: $showNewProfileSheet) {
            newProfileSheet
        }
    }

    private var captureHint: String {
        if let target = captureTarget {
            return "Press a key to assign to \(target)..."
        }
        return "Click a key to remap it. Right-click to clear."
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "gamecontroller.fill").font(.title2)
            Text("G13").font(.title2).fontWeight(.bold)
            Spacer()
            Circle()
                .fill(device.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(device.isConnected ? "Connected" : "Disconnected")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Profile bar

    private var profileBar: some View {
        HStack(spacing: 8) {
            Text("Profile:").font(.caption).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(profileManager.profiles.enumerated()), id: \.element.id) { index, profile in
                        profileTab(index: index, profile: profile)
                    }
                }
            }

            Spacer()

            Button(action: {
                newProfileName = "New Profile"
                showNewProfileSheet = true
            }) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .help("Add a new profile")
        }
    }

    private func profileTab(index: Int, profile: G13Profile) -> some View {
        let isActive = index == profileManager.activeProfileIndex

        // Build the profile's backlight color for the tab
        let profileColor = Color(
            red: Double(profile.backlightR) / 255.0,
            green: Double(profile.backlightG) / 255.0,
            blue: Double(profile.backlightB) / 255.0
        )

        return Button(action: {
            profileManager.switchToProfile(at: index)
            applyActiveProfile()
            statusMessage = "Switched to \(profile.name)"
        }) {
            HStack(spacing: 4) {
                // Color dot showing the profile's backlight color
                Circle()
                    .fill(profileColor)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 0.5))

                // M1/M2/M3 badge for the first 3 profiles
                if index < 3 {
                    Text("M\(index + 1)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.3)))
                }
                Text(profile.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? profileColor.opacity(0.2) : Color(nsColor: .controlColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? profileColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename...") {
                let alert = NSAlert()
                alert.messageText = "Rename Profile"
                alert.informativeText = "Enter a new name for this profile:"
                let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                textField.stringValue = profile.name
                alert.accessoryView = textField
                alert.addButton(withTitle: "Rename")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
                    if !newName.isEmpty {
                        profileManager.renameProfile(at: index, to: newName)
                        statusMessage = "Profile renamed to \(newName)"
                    }
                }
            }
            Button("Duplicate") {
                profileManager.addProfile(name: profile.name + " copy")
                statusMessage = "Profile duplicated"
            }
            Divider()
            Button("Delete", role: .destructive) {
                if profileManager.profiles.count > 1 {
                    profileManager.deleteProfile(at: index)
                    applyActiveProfile()
                    statusMessage = "Profile deleted"
                } else {
                    statusMessage = "Cannot delete the last profile"
                }
            }
            .disabled(profileManager.profiles.count <= 1)
        }
    }

    // MARK: - New profile sheet

    private var newProfileSheet: some View {
        VStack(spacing: 16) {
            Text("New Profile").font(.headline)
            TextField("Profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
            HStack {
                Button("Cancel") {
                    showNewProfileSheet = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let name = newProfileName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        profileManager.addProfile(name: name)
                        profileManager.switchToProfile(at: profileManager.profiles.count - 1)
                        applyActiveProfile()
                        statusMessage = "Created profile: \(name)"
                    }
                    showNewProfileSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Accessibility status

    private var accessibilityStatus: some View {
        GroupBox("Accessibility") {
            if keyMapper.hasAccessibility {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Granted").font(.caption)
                }
            } else {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Required").font(.caption)
                    }
                    Button("Grant access") {
                        keyMapper.checkAccessibility()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Key layout

    private var keyboardLayout: some View {
        VStack(spacing: 5) {
            // Row 1: G1-G7
            HStack(spacing: 4) {
                keyButton("G1"); keyButton("G2"); keyButton("G3")
                keyButton("G4"); keyButton("G5"); keyButton("G6"); keyButton("G7")
            }
            // Row 2: G8-G14
            HStack(spacing: 4) {
                keyButton("G8"); keyButton("G9"); keyButton("G10")
                keyButton("G11"); keyButton("G12"); keyButton("G13"); keyButton("G14")
            }
            // Row 3: G15-G19, centered
            HStack(spacing: 4) {
                keyButton("G15", width: 64); keyButton("G16"); keyButton("G17")
                keyButton("G18"); keyButton("G19")
            }
            // Row 4: G20-G22, centered
            HStack(spacing: 4) {
                keyButton("G20", width: 64); keyButton("G21", width: 56)
                keyButton("G22", width: 96)
            }
        }
    }

    private var specialButtons: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LCD buttons").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    keyButton("BD", width: 40); keyButton("L1", width: 40)
                    keyButton("L2", width: 40); keyButton("L3", width: 40)
                    keyButton("L4", width: 40)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Thumb buttons").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    keyButton("LEFT", width: 70, displayLabel: "Left")
                    keyButton("RIGHT", width: 70, displayLabel: "Bottom")
                }
            }
        }
    }

    // MARK: - Key button

    private func keyButton(_ key: String, width: CGFloat = 52, displayLabel: String? = nil) -> some View {
        let isSelected = captureTarget == key && !captureIsJoystick
        let isPressed = device.pressedKeys.contains(key)
        let mapping = profileManager.keyMapping[key]

        return VStack(spacing: 0) {
            Button(action: {
                selectTarget(key: key, isJoystick: false)
            }) {
                VStack(spacing: 2) {
                    Text(displayLabel ?? key)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text(mapping?.displayName ?? "--")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: width, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.accentColor.opacity(0.3)
                              : isPressed ? Color.orange.opacity(0.3)
                              : Color(nsColor: .controlColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.accentColor
                                : isPressed ? Color.orange
                                : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Clear mapping") {
                    profileManager.clearKey(key)
                    statusMessage = "\(key) mapping cleared"
                }
            }
        }
    }

    // MARK: - Joystick config

    private var joystickConfig: some View {
        GroupBox("Joystick") {
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    joystickDirButton("UP", label: "Up")
                    HStack(spacing: 2) {
                        joystickDirButton("LEFT", label: "Left")
                        joystickClickButton()
                        joystickDirButton("RIGHT", label: "Right")
                    }
                    joystickDirButton("DOWN", label: "Down")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Click a direction,")
                        .font(.caption).foregroundColor(.secondary)
                    Text("then press the key")
                        .font(.caption).foregroundColor(.secondary)
                    Text("to assign.")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer().frame(height: 8)
                    Text("Default: WASD")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("Right-click to clear.")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func joystickClickButton() -> some View {
        let key = "STICK"
        let isSelected = captureTarget == key && !captureIsJoystick
        let isPressed = device.pressedKeys.contains(key)
        let mapping = profileManager.keyMapping[key]

        return Button(action: {
            selectTarget(key: key, isJoystick: false)
        }) {
            VStack(spacing: 2) {
                Text("Click")
                    .font(.system(size: 9, weight: .bold))
                Text(mapping?.displayName ?? "--")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 56, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.3)
                          : isPressed ? Color.orange.opacity(0.3)
                          : Color(nsColor: .controlColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.accentColor
                            : isPressed ? Color.orange
                            : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Clear mapping") {
                profileManager.clearKey(key)
                statusMessage = "STICK mapping cleared"
            }
        }
    }

    private func joystickDirButton(_ direction: String, label: String) -> some View {
        let isSelected = captureTarget == direction && captureIsJoystick
        let mapping = profileManager.joystickMapping[direction]
        let isActive: Bool = {
            switch direction {
            case "UP":    return keyMapper.joyUp
            case "DOWN":  return keyMapper.joyDown
            case "LEFT":  return keyMapper.joyLeft
            case "RIGHT": return keyMapper.joyRight
            default:      return false
            }
        }()

        return Button(action: {
            selectTarget(key: direction, isJoystick: true)
        }) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                Text(mapping?.displayName ?? "--")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 56, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.3)
                          : isActive ? Color.orange.opacity(0.3)
                          : Color(nsColor: .controlColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.accentColor
                            : isActive ? Color.orange
                            : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Clear mapping") {
                profileManager.clearJoystickDirection(direction)
                statusMessage = "Joystick \(direction) mapping cleared"
            }
        }
    }

    // MARK: - Backlight

    private var backlightControls: some View {
        GroupBox("Backlight") {
            VStack(spacing: 8) {
                colorSlider("R", value: Binding(
                    get: { Double(profileManager.backlightR) },
                    set: { profileManager.backlightR = UInt8($0); applyBacklightLive() }
                ), color: .red)
                colorSlider("G", value: Binding(
                    get: { Double(profileManager.backlightG) },
                    set: { profileManager.backlightG = UInt8($0); applyBacklightLive() }
                ), color: .green)
                colorSlider("B", value: Binding(
                    get: { Double(profileManager.backlightB) },
                    set: { profileManager.backlightB = UInt8($0); applyBacklightLive() }
                ), color: .blue)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(
                        red: Double(profileManager.backlightR) / 255,
                        green: Double(profileManager.backlightG) / 255,
                        blue: Double(profileManager.backlightB) / 255
                    ))
                    .frame(height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.2)))
            }
            .padding(.vertical, 4)
        }
    }

    private func colorSlider(_ label: String, value: Binding<Double>, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).frame(width: 12)
            Slider(value: value, in: 0...255, step: 1) { editing in
                if !editing {
                    profileManager.save()
                }
            }
            .tint(color)
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 28, alignment: .trailing)
        }
    }

    // MARK: - Joystick live

    private var joystickLiveInfo: some View {
        GroupBox("Joystick position") {
            VStack(spacing: 4) {
                HStack {
                    Text("X: \(device.joystickX)")
                    Spacer()
                    Text("Y: \(device.joystickY)")
                }
                .font(.system(size: 11, design: .monospaced))

                HStack {
                    Text("Deadzone:").font(.caption)
                    Slider(
                        value: Binding(
                            get: { Double(profileManager.joystickDeadzone) },
                            set: { profileManager.joystickDeadzone = Int($0) }
                        ),
                        in: 5...80, step: 5
                    ) { editing in
                        if !editing { profileManager.save() }
                    }
                    Text("\(profileManager.joystickDeadzone)")
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 24)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func selectTarget(key: String, isJoystick: Bool) {
        if captureTarget == key && captureIsJoystick == isJoystick {
            captureTarget = nil
            statusMessage = ""
        } else {
            captureTarget = key
            captureIsJoystick = isJoystick
            let prefix = isJoystick ? "Joystick " : ""
            statusMessage = "\(prefix)\(key): press a key to assign..."
        }
    }

    private func applyBacklightLive() {
        device.setBacklightColor(
            red: profileManager.backlightR,
            green: profileManager.backlightG,
            blue: profileManager.backlightB
        )
    }

    private func applyActiveProfile() {
        device.setBacklightColor(
            red: profileManager.backlightR,
            green: profileManager.backlightG,
            blue: profileManager.backlightB
        )
        let mLed: UInt8
        switch profileManager.activeProfileIndex {
        case 0:  mLed = 0x01
        case 1:  mLed = 0x02
        case 2:  mLed = 0x04
        default: mLed = 0x00
        }
        device.setMLEDs(mLed)
    }

    private func handleKeyCaptured(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard let target = captureTarget else { return }


        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("CMD") }
        if modifiers.contains(.control) { parts.append("CTRL") }
        if modifiers.contains(.option)  { parts.append("ALT") }
        if modifiers.contains(.shift)   { parts.append("SHIFT") }

        let keyName = KeyMapper.macKeycodes.first(where: { $0.value == keyCode })?.key

        if let keyName = keyName {
            let modifierNames: Set<String> = [
                "SHIFT", "LEFTSHIFT", "RIGHTSHIFT",
                "CTRL", "CONTROL", "ALT", "OPTION",
                "CMD", "COMMAND", "CAPSLOCK"
            ]
            if modifierNames.contains(keyName) {
                parts = [keyName]
            } else {
                parts.append(keyName)
            }
        } else {
            statusMessage = "Unknown key (code: \(keyCode))"
            return
        }

        let actionString = parts.joined(separator: "+")

        if captureIsJoystick {
            profileManager.setJoystickDirection(target, to: actionString)
            statusMessage = "Joystick \(target) -> \(actionString)"
        } else {
            profileManager.setKey(target, to: actionString)
            statusMessage = "\(target) -> \(actionString)"
        }
        captureTarget = nil
    }
}

// MARK: - KeyCaptureView

struct KeyCaptureView: NSViewRepresentable {
    var isCapturing: Bool
    var onKeyCaptured: (UInt16, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyCaptured = onKeyCaptured
        view.isCapturing = isCapturing
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyCaptured = onKeyCaptured
        nsView.isCapturing = isCapturing
        if isCapturing {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

class KeyCaptureNSView: NSView {
    var onKeyCaptured: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var isCapturing: Bool = false

    // Track whether a modifier was pressed alone (no other key in between)
    private var modifierOnlyKeyCode: UInt16? = nil

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if isCapturing {
            // A real key was pressed while modifiers might be held.
            // Clear the modifier-only tracker since this is a combo.
            modifierOnlyKeyCode = nil
            onKeyCaptured?(event.keyCode, event.modifierFlags)
        } else {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if isCapturing {
            let modFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !modFlags.isEmpty {
                // A modifier was just pressed -- remember it but don't capture yet.
                // If keyDown fires before the modifier is released, it's a combo.
                // If the modifier is released without keyDown, it's a standalone modifier.
                modifierOnlyKeyCode = event.keyCode
            } else {
                // All modifiers released. If we still have a pending modifier
                // (no keyDown happened), capture it as a standalone modifier.
                if let keyCode = modifierOnlyKeyCode {
                    onKeyCaptured?(keyCode, NSEvent.ModifierFlags())
                }
                modifierOnlyKeyCode = nil
            }
        } else {
            super.flagsChanged(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isCapturing {
            window?.makeFirstResponder(self)
        }
    }
}
