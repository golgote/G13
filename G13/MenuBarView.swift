// =============================================================
//  MenuBarView.swift
//  Drop-down menu in the macOS menu bar
// =============================================================

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var device: G13Device
    @ObservedObject var keyMapper: KeyMapper
    @ObservedObject var profileManager: ProfileManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Connection status
            HStack {
                Circle()
                    .fill(device.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(device.isConnected ? "G13 connected" : "G13 disconnected")
            }

            if keyMapper.hasAccessibility {
                HStack {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Key remapping active")
                }
            } else {
                Button("Grant Accessibility...") {
                    keyMapper.checkAccessibility()
                }
            }

            Divider()

            // Profile selector
            Text("Profile").font(.caption).foregroundColor(.secondary)
            ForEach(Array(profileManager.profiles.enumerated()), id: \.element.id) { index, profile in
                Button(action: {
                    switchProfile(index)
                }) {
                    HStack {
                        if index == profileManager.activeProfileIndex {
                            Image(systemName: "checkmark")
                        }
                        Text(profile.name)
                        if index < 3 {
                            Spacer()
                            Text("M\(index + 1)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()

            // Backlight presets
            Text("Backlight").font(.caption).foregroundColor(.secondary)
            Button("Red")    { setColor(255, 0, 0) }
            Button("Green")  { setColor(0, 255, 0) }
            Button("Blue")   { setColor(0, 80, 255) }
            Button("White")  { setColor(255, 255, 255) }
            Button("Purple") { setColor(128, 0, 255) }

            Divider()

            Button("Settings...") {
                showSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit G13") {
                device.stopMonitoring()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
        .onAppear {
            startG13()
        }
    }

    // MARK: - Setup

    private func startG13() {
        keyMapper.checkAccessibility()
        setupCallbacks()
        device.startMonitoring()
    }

    // Register all callbacks. These will be invoked on every connect/disconnect,
    // including the initial connection and any subsequent reconnections.
    private func setupCallbacks() {
        device.onDeviceConnected = {
            applyActiveProfile()
            updateLCDStatus()
        }

        device.onDeviceDisconnected = {
            // Nothing special needed; the UI updates automatically
            // via the @Published isConnected property.
            print("[MenuBarView] G13 disconnected, waiting for reconnection...")
        }

        device.onKeyChanged = { name, isPressed in
            if !keyMapper.hasAccessibility {
                keyMapper.checkAccessibility()
            }

            keyMapper.handleKey(
                name: name, isPressed: isPressed,
                mapping: profileManager.keyMapping
            )

            // M1/M2/M3 switch profiles
            if isPressed {
                switch name {
                case "M1":
                    if profileManager.profiles.count > 0 { switchProfile(0) }
                case "M2":
                    if profileManager.profiles.count > 1 { switchProfile(1) }
                case "M3":
                    if profileManager.profiles.count > 2 { switchProfile(2) }
                default: break
                }
            }
        }

        device.onJoystickChanged = { x, y in
            keyMapper.handleJoystickArrows(
                x: x, y: y,
                deadzone: profileManager.joystickDeadzone,
                mapping: profileManager.joystickMapping
            )
        }
    }

    private func switchProfile(_ index: Int) {
        profileManager.switchToProfile(at: index)
        applyActiveProfile()
        updateLCDStatus()
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

    private func updateLCDStatus() {
        device.lcd.clear()
        device.lcd.drawRect(x: 0, y: 0, width: G13LCD.width, height: G13LCD.height)
        device.lcd.drawText("G13", x: 2, y: 2)
        device.lcd.drawHLine(y: 10)

        let name = profileManager.activeProfileName
        let displayName = String(name.prefix(24))
        device.lcd.drawText(displayName, x: 2, y: 14)

        let num = "[\(profileManager.activeProfileIndex + 1)/\(profileManager.profiles.count)]"
        device.lcd.drawText(num, x: 2, y: 26)

        device.updateLCD()
    }

    private func setColor(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        device.setBacklightColor(red: r, green: g, blue: b)
        profileManager.backlightR = r
        profileManager.backlightG = g
        profileManager.backlightB = b
    }

    private func showSettingsWindow() {
        SettingsWindowController.shared.show(
            device: device,
            keyMapper: keyMapper,
            profileManager: profileManager
        )
    }
}
