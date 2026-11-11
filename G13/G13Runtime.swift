import AppKit
import SwiftUI
import Combine

// Owns the HID connection and callbacks independently of whether a menu is open.
final class G13Runtime: ObservableObject {
    static let shared = G13Runtime()
    let device = G13Device()
    let keyMapper = KeyMapper()
    let profileManager = ProfileManager()
    @Published private(set) var isSafeTestMode = false
    @Published private(set) var testEvents: [String] = []
    @Published private(set) var displayButtonsControlLCD =
        (UserDefaults.standard.object(forKey: "g13DisplayButtonsControlLCD") as? Bool) ?? true
    @Published private(set) var displayPage: G13DisplayPage = .overview
    private var appObserver: NSObjectProtocol?
    private var displayTimer: Timer?
    private let systemMonitor = G13SystemMonitor()
    private var systemSnapshot: G13SystemSnapshot?
    private var started = false
    private var lastPreviewJoystick = ""

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        keyMapper.checkAccessibility()
        profileManager.beforeInputConfigurationChange = { [weak self] in self?.keyMapper.releaseAllKeys() }
        profileManager.onSelectionChanged = { [weak self] in self?.applyActiveProfile() }
        device.onDeviceConnected = { [weak self] in self?.applyActiveProfile() }
        device.onDeviceDisconnected = { [weak self] in self?.keyMapper.releaseAllKeys() }
        device.onKeyChanged = { [weak self] name, pressed in
            guard let self else { return }
            if self.displayButtonsControlLCD && ["BD", "L1", "L2", "L3", "L4"].contains(name) {
                if pressed { self.handleDisplayButton(name) }
                return
            }
            switch name {
            case "M1", "M2", "M3":
                if pressed, let digit = name.last?.wholeNumberValue {
                    self.profileManager.switchLayer(digit)
                    if self.isSafeTestMode { self.recordTest("\(name) → select layer") }
                }
            case "MR":
                if pressed {
                    if self.isSafeTestMode { self.recordTest("MR → new command") }
                    SettingsWindowController.shared.show(runtime: self, openRecorder: true)
                }
            default:
                if self.isSafeTestMode {
                    if pressed { self.previewKey(name) }
                    return
                }
                let assignment = self.profileManager.outputRawKeyMapping[name] ?? ""
                if let command = self.profileManager.outputCommand(for: assignment),
                   command.kind == .multiKey {
                    if pressed {
                        self.keyMapper.playSequence(source: name, steps: command.steps,
                                                    delayMilliseconds: command.delayMilliseconds)
                    }
                } else if let command = self.profileManager.outputCommand(for: assignment),
                          command.kind == .keystroke,
                          let hold = command.holdMilliseconds {
                    if pressed, let shortcut = command.steps.first {
                        self.keyMapper.startTimedHold(source: name, shortcut: shortcut,
                                                      durationMilliseconds: hold)
                    }
                } else if let command = self.profileManager.outputCommand(for: assignment),
                          command.kind == .mouseFunction {
                    if pressed, let action = command.mouseAction {
                        self.keyMapper.performMouseAction(action, modifiers: command.mouseModifiers ?? [])
                    }
                } else {
                    self.keyMapper.handleKey(name: name, isPressed: pressed,
                                             mapping: self.profileManager.outputKeyMapping)
                }
            }
        }
        device.onJoystickChanged = { [weak self] x, y in
            guard let self else { return }
            if self.isSafeTestMode {
                self.previewJoystick(x: x, y: y)
                return
            }
            let mode = self.profileManager.outputJoystickMode
            switch mode {
            case .keys:
                self.keyMapper.handleJoystickArrows(x: x, y: y,
                    deadzone: self.profileManager.outputJoystickDeadzone,
                    mapping: self.profileManager.outputJoystickMapping)
            case .verticalScroll, .horizontalScroll, .twoAxisScroll:
                guard self.profileManager.outputProfile != nil else {
                    self.keyMapper.releaseAllKeys()
                    return
                }
                self.keyMapper.handleJoystickArrows(x: x, y: y,
                    deadzone: self.profileManager.outputJoystickDeadzone,
                    mapping: self.profileManager.outputJoystickMapping,
                    vertical: mode == .horizontalScroll,
                    horizontal: mode == .verticalScroll)
                self.keyMapper.handleJoystickScroll(x: x, y: y,
                    deadzone: self.profileManager.outputJoystickDeadzone,
                    verticalSpeed: self.profileManager.outputJoystickScrollSpeed,
                    horizontalSpeed: self.profileManager.outputJoystickHorizontalScrollSpeed,
                    vertical: mode != .horizontalScroll,
                    horizontal: mode != .verticalScroll)
            }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            if bundleID == Bundle.main.bundleIdentifier {
                self.profileManager.setEditorFrontmost()
            } else {
                self.profileManager.activateProfile(for: bundleID)
            }
        }
        if let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if frontmostID == Bundle.main.bundleIdentifier {
                profileManager.setEditorFrontmost()
            } else {
                profileManager.activateProfile(for: frontmostID)
            }
        }
        device.startMonitoring()
        startDisplayTimerIfNeeded()
    }

    func stop() {
        keyMapper.releaseAllKeys()
        displayTimer?.invalidate()
        displayTimer = nil
        device.stopMonitoring()
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
    }

    func setSafeTestMode(_ enabled: Bool) {
        guard isSafeTestMode != enabled else { return }
        keyMapper.releaseAllKeys()
        lastPreviewJoystick = ""
        if enabled { testEvents = [] }
        isSafeTestMode = enabled
    }

    func setDisplayButtonsControlLCD(_ enabled: Bool) {
        guard displayButtonsControlLCD != enabled else { return }
        keyMapper.releaseAllKeys()
        displayButtonsControlLCD = enabled
        UserDefaults.standard.set(enabled, forKey: "g13DisplayButtonsControlLCD")
        displayPage = .overview
        if enabled { startDisplayTimerIfNeeded() }
        else {
            displayTimer?.invalidate()
            displayTimer = nil
        }
        applyActiveProfile()
    }

    private func startDisplayTimerIfNeeded() {
        guard started, displayButtonsControlLCD, displayTimer == nil else { return }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.displayPage == .system {
                self.systemSnapshot = self.systemMonitor.sample()
                self.renderLCD()
            }
        }
    }

    func showDisplayPage(_ page: G13DisplayPage) {
        guard displayButtonsControlLCD else { return }
        displayPage = page
        if page == .system { systemSnapshot = systemMonitor.sample() }
        renderLCD()
    }

    private func handleDisplayButton(_ name: String) {
        if name == "L4" { return }
        switch name {
        case "BD":
            showDisplayPage(displayPage.next)
        case "L1", "L2":
            if displayPage == .profiles {
                let direction = name == "L1" ? -1 : 1
                let count = profileManager.profiles.count
                if count > 0 {
                    profileManager.switchToProfile(at: (profileManager.activeProfileIndex + direction + count) % count)
                }
            }
        case "L3":
            if displayPage == .profiles { profileManager.setStartupProfileToActive() }
        default: break
        }
        if isSafeTestMode && (name == "BD" || displayPage == .profiles) {
            let description = name == "L3" ? "save startup profile" : displayPage.title
            recordTest("\(name) → \(description)")
        }
        renderLCD()
    }

    private func recordTest(_ message: String) {
        testEvents.insert(message, at: 0)
        if testEvents.count > 6 { testEvents.removeLast() }
    }

    private func previewKey(_ name: String) {
        let raw = (profileManager.editorIsFrontmost ? profileManager.activeRawKeyMapping :
                   profileManager.outputRawKeyMapping)[name] ?? ""
        let action: String
        let command = profileManager.editorIsFrontmost ? profileManager.command(for: raw) :
            profileManager.outputCommand(for: raw)
        if let command {
            action = "\(command.name) (\(command.actionDescription))"
        } else if raw.hasPrefix("@") {
            action = "unavailable command"
        } else if !raw.isEmpty {
            action = raw
        } else {
            action = "unassigned"
        }
        recordTest("\(name) → \(action)")
    }

    private func previewJoystick(x: UInt8, y: UInt8) {
        let deadzone = profileManager.editorIsFrontmost ? profileManager.joystickDeadzone :
            profileManager.outputJoystickDeadzone
        let up = Int(y) < 128 - deadzone
        let down = Int(y) > 128 + deadzone
        let left = Int(x) < 128 - deadzone
        let right = Int(x) > 128 + deadzone
        let directions = [("UP", up), ("DOWN", down), ("LEFT", left), ("RIGHT", right)]
            .filter { $0.1 }.map { $0.0 }
        let state = directions.joined(separator: "+")
        guard state != lastPreviewJoystick else { return }
        lastPreviewJoystick = state
        guard !directions.isEmpty else { return }
        let mode = profileManager.editorIsFrontmost ? profileManager.activeJoystickMode :
            profileManager.outputJoystickMode
        let mapping = profileManager.editorIsFrontmost ? profileManager.joystickMapping :
            profileManager.outputJoystickMapping
        let descriptions = directions.map { direction in
            mode.scrolls(direction) ? "\(direction) → scroll" :
                "\(direction) → \(mapping[direction]?.displayName ?? "unassigned")"
        }
        recordTest("Joystick: " + descriptions.joined(separator: ", ") + " (no output sent)")
    }

    func applyActiveProfile() {
        let color = profileManager.outputBacklightColor
        device.setBacklightColor(red: UInt8(color.red),
                                 green: UInt8(color.green),
                                 blue: UInt8(color.blue))
        device.setMLEDs(UInt8(1 << (profileManager.activeLayer - 1)))
        renderLCD()
    }

    private func renderLCD() {
        let lcd = device.lcd
        lcd.clear()
        lcd.drawRect(x: 0, y: 0, width: G13LCD.width, height: G13LCD.height)
        if !displayButtonsControlLCD {
            lcd.drawText("G13  M\(profileManager.activeLayer)", x: 2, y: 2)
            lcd.drawHLine(y: 10)
            lcd.drawText(lcdText(profileManager.outputProfileName, limit: 25), x: 2, y: 14)
            device.updateLCD()
            return
        }
        switch displayPage {
        case .overview:
            lcd.drawText("G13 STUDIO", x: 2, y: 2)
            lcd.drawHLine(y: 10)
            lcd.drawText(lcdText(profileManager.outputProfileName, limit: 25), x: 2, y: 17)
            lcd.drawText("M\(profileManager.activeLayer)", x: 2, y: 30)
        case .profiles:
            lcd.drawText("PROFILES  *=START", x: 2, y: 1)
            lcd.drawHLine(y: 8)
            let rows = G13LCDLayout.profileRows(
                names: profileManager.profiles.map(\.name),
                activeIndex: profileManager.activeProfileIndex,
                startupIndex: profileManager.profiles.firstIndex { $0.id == profileManager.startupProfileID }
            )
            for (row, text) in rows.enumerated() {
                lcd.drawText(lcdText(text, limit: 25), x: 2, y: 10 + row * 9)
            }
            lcd.drawProfileSoftKeys()
        case .system:
            let snapshot = systemSnapshot ?? systemMonitor.sample()
            systemSnapshot = snapshot
            lcd.drawText("CPU \(snapshot.cpuPercent.map { "\($0)%" } ?? "...")", x: 2, y: 2)
            drawUsageBar(snapshot.cpuPercent ?? 0, y: 11)
            let memory = snapshot.usedMemoryGiB.map { String(format: "%.1f", $0) } ?? "?"
            lcd.drawText("RAM \(memory)/\(String(format: "%.1f", snapshot.totalMemoryGiB)) GiB", x: 2, y: 22)
            let percent = Int(100 * (snapshot.usedMemoryGiB ?? 0) / max(0.1, snapshot.totalMemoryGiB))
            drawUsageBar(percent, y: 31)
        }
        device.updateLCD()
    }

    private func drawUsageBar(_ percent: Int, y: Int) {
        let amount = max(0, min(100, percent))
        device.lcd.drawRect(x: 2, y: y, width: 156, height: 7)
        device.lcd.fillRect(x: 3, y: y + 1, width: amount * 154 / 100, height: 5)
    }

    private func lcdText(_ value: String, limit: Int) -> String {
        String(value.prefix(limit).map { G13LCD.font5x7[$0] == nil ? " " : $0 })
    }
}

final class G13AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        G13Runtime.shared.start()
        SettingsWindowController.shared.show(runtime: G13Runtime.shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        G13Runtime.shared.stop()
    }
}
