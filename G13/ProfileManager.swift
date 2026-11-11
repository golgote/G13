// =============================================================
//  ProfileManager.swift
//  Multi-profile preferences management via UserDefaults
// =============================================================

import Foundation
import Combine

struct G13BacklightColor: Codable, Equatable {
    var red: Int
    var green: Int
    var blue: Int

    init(red: Int, green: Int, blue: Int) {
        self.red = min(max(red, 0), 255)
        self.green = min(max(green, 0), 255)
        self.blue = min(max(blue, 0), 255)
    }
}

enum G13JoystickMode: String, Codable, CaseIterable {
    case keys
    case verticalScroll
    case horizontalScroll
    case twoAxisScroll

    var label: String {
        switch self {
        case .keys: return "Keys"
        case .verticalScroll: return "Vertical scroll"
        case .horizontalScroll: return "Horizontal scroll"
        case .twoAxisScroll: return "Both axes scroll"
        }
    }

    func scrolls(_ direction: String) -> Bool {
        switch self {
        case .keys: return false
        case .verticalScroll: return direction == "UP" || direction == "DOWN"
        case .horizontalScroll: return direction == "LEFT" || direction == "RIGHT"
        case .twoAxisScroll: return ["UP", "DOWN", "LEFT", "RIGHT"].contains(direction)
        }
    }
}

// A single profile containing all settings for a specific use case
struct G13Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var keyMapping: [String: String]       // G13 key name -> action string (e.g. "CMD+C")
    var joystickMapping: [String: String]   // direction -> action string
    var backlightR: Int
    var backlightG: Int
    var backlightB: Int
    var joystickDeadzone: Int
    // Added as optional values so profiles saved by earlier releases still decode.
    var m2KeyMapping: [String: String]?
    var m3KeyMapping: [String: String]?
    var m2JoystickMapping: [String: String]?
    var m3JoystickMapping: [String: String]?
    var applicationBundleID: String?
    var applicationDisplayName: String?
    // Missing values in older profiles inherit the M1 color until edited.
    var m2BacklightColor: G13BacklightColor?
    var m3BacklightColor: G13BacklightColor?
    var isUniversalDefault: Bool?
    var keyIcons: [String: String]?
    var m2KeyIcons: [String: String]?
    var m3KeyIcons: [String: String]?
    var keyIconColors: [String: String]?
    var m2KeyIconColors: [String: String]?
    var m3KeyIconColors: [String: String]?
    var autoSwitch: Bool?
    var joystickMode: G13JoystickMode?
    var m2JoystickMode: G13JoystickMode?
    var m3JoystickMode: G13JoystickMode?
    var joystickScrollSpeed: Int?
    var joystickHorizontalScrollSpeed: Int?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.keyMapping = [:]
        self.joystickMapping = [:]
        self.backlightR = 0
        self.backlightG = 80
        self.backlightB = 255
        self.joystickDeadzone = 20
        self.m2KeyMapping = [:]
        self.m3KeyMapping = [:]
        self.m2JoystickMapping = [:]
        self.m3JoystickMapping = [:]
        self.applicationBundleID = nil
        self.applicationDisplayName = nil
        self.m2BacklightColor = nil
        self.m3BacklightColor = nil
        self.isUniversalDefault = false
        self.keyIcons = [:]
        self.m2KeyIcons = [:]
        self.m3KeyIcons = [:]
        self.keyIconColors = [:]
        self.m2KeyIconColors = [:]
        self.m3KeyIconColors = [:]
        self.autoSwitch = false
        self.joystickMode = .keys
        self.m2JoystickMode = .keys
        self.m3JoystickMode = .keys
        self.joystickScrollSpeed = 2
        self.joystickHorizontalScrollSpeed = 2
    }

    // Create a profile from the default WASD gaming layout
    static func defaultGaming() -> G13Profile {
        var profile = G13Profile(name: "Gaming (WASD)")
        profile.keyMapping = defaultKeyMapping
        profile.joystickMapping = defaultJoystickMapping
        profile.backlightR = 0
        profile.backlightG = 80
        profile.backlightB = 255
        return profile
    }

    // Default key mapping for gaming
    static let defaultKeyMapping: [String: String] = [
        "G1":  "ESC",   "G2":  "TAB",  "G3":  "Q",
        "G4":  "W",     "G5":  "E",    "G6":  "R",    "G7":  "T",
        "G8":  "I",     "G9":  "M",    "G10": "A",
        "G11": "S",     "G12": "D",    "G13": "F",    "G14": "G",
        "G15": "SHIFT", "G16": "Z",    "G17": "X",
        "G18": "C",     "G19": "V",
        "G20": "CTRL",  "G21": "ALT",  "G22": "SPACE",
        "LEFT":  "F1",  "RIGHT": "F2", "STICK": "F3",
        "BD":    "F5",
        "L1":    "F9",  "L2": "F10",   "L3": "F11",   "L4": "F12",
    ]

    static let defaultJoystickMapping: [String: String] = [
        "UP": "W", "DOWN": "S", "LEFT": "A", "RIGHT": "D",
    ]
}

class ProfileManager: ObservableObject {

    // All profiles
    @Published var profiles: [G13Profile] = []

    // Index of the currently active profile
    @Published var activeProfileIndex: Int = 0
    @Published var activeLayer: Int = 1
    @Published var commands: [G13Command] = []
    @Published var commandFolders: [G13CommandFolder] = []
    @Published var inputSuppressed = false
    @Published private(set) var editorIsFrontmost = false
    @Published private(set) var frontmostBundleID: String?
    private var manualOutputProfileID: UUID?
    @Published private(set) var startupProfileID: UUID?

    private let defaults: UserDefaults
    // The event generator owns key-up events; release them before any change
    // that could alter the mapping for a currently held physical control.
    var beforeInputConfigurationChange: (() -> Void)?
    var onSelectionChanged: (() -> Void)?

    var activeProfile: G13Profile? {
        profiles.indices.contains(activeProfileIndex) ? profiles[activeProfileIndex] : nil
    }

    // Keep the selected profile in the editor, while output follows the
    // frontmost application. Unmatched apps use the universal Default profile.
    var outputProfileIndex: Int? {
        guard !editorIsFrontmost else { return nil }
        if let manualOutputProfileID,
           let index = profiles.firstIndex(where: { $0.id == manualOutputProfileID }) {
            let profile = profiles[index]
            if profile.applicationBundleID == nil ||
               profile.applicationBundleID?.caseInsensitiveCompare(frontmostBundleID ?? "") == .orderedSame {
                return index
            }
            return universalDefaultIndex
        }
        if let bundleID = frontmostBundleID {
            if let active = activeProfile,
               active.applicationBundleID?.caseInsensitiveCompare(bundleID) == .orderedSame {
                return activeProfileIndex
            }
            if let match = profiles.firstIndex(where: {
                $0.applicationBundleID?.caseInsensitiveCompare(bundleID) == .orderedSame &&
                $0.autoSwitch != false
            }) { return match }
        }
        if let active = activeProfile, active.applicationBundleID == nil,
           active.isUniversalDefault != true { return activeProfileIndex }
        return universalDefaultIndex
    }

    var outputProfile: G13Profile? {
        outputProfileIndex.flatMap { profiles.indices.contains($0) ? profiles[$0] : nil }
    }

    var outputProfileName: String { outputProfile?.name ?? activeProfileName }

    func setEditorFrontmost() {
        guard !editorIsFrontmost else { return }
        beforeInputConfigurationChange?()
        editorIsFrontmost = true
        onSelectionChanged?()
    }

    var universalDefaultIndex: Int? {
        profiles.firstIndex { $0.isUniversalDefault == true }
    }

    var activeProfileIsUniversal: Bool {
        activeProfile?.isUniversalDefault == true
    }

    var startupProfileName: String {
        profiles.first(where: { $0.id == startupProfileID })?.name ?? "Default (All Apps)"
    }

    var activeIsStartupProfile: Bool { activeProfile?.id == startupProfileID }

    func setStartupProfileToActive() {
        guard let id = activeProfile?.id else { return }
        startupProfileID = id
        save()
        onSelectionChanged?()
    }

    var autoSwitchEnabled: Bool {
        activeProfile?.applicationBundleID != nil && activeProfile?.autoSwitch != false
    }

    func setAutoSwitchEnabled(_ enabled: Bool) {
        guard profiles.indices.contains(activeProfileIndex),
              profiles[activeProfileIndex].applicationBundleID != nil else { return }
        beforeInputConfigurationChange?()
        profiles[activeProfileIndex].autoSwitch = enabled
        save()
        onSelectionChanged?()
    }

    var activeJoystickMode: G13JoystickMode {
        get {
            guard let profile = activeProfile else { return .keys }
            switch activeLayer {
            case 2: return profile.m2JoystickMode ?? .keys
            case 3: return profile.m3JoystickMode ?? .keys
            default: return profile.joystickMode ?? .keys
            }
        }
        set {
            guard profiles.indices.contains(activeProfileIndex) else { return }
            beforeInputConfigurationChange?()
            switch activeLayer {
            case 2: profiles[activeProfileIndex].m2JoystickMode = newValue
            case 3: profiles[activeProfileIndex].m3JoystickMode = newValue
            default: profiles[activeProfileIndex].joystickMode = newValue
            }
            save()
        }
    }

    var activeJoystickScrollSpeed: Int {
        get { min(max(activeProfile?.joystickScrollSpeed ?? 2, 1), 5) }
        set {
            guard profiles.indices.contains(activeProfileIndex) else { return }
            profiles[activeProfileIndex].joystickScrollSpeed = min(max(newValue, 1), 5)
            save()
        }
    }

    var activeJoystickHorizontalScrollSpeed: Int {
        get { min(max(activeProfile?.joystickHorizontalScrollSpeed ?? activeProfile?.joystickScrollSpeed ?? 2, 1), 5) }
        set {
            guard profiles.indices.contains(activeProfileIndex) else { return }
            profiles[activeProfileIndex].joystickHorizontalScrollSpeed = min(max(newValue, 1), 5)
            save()
        }
    }

    private func ensureUniversalDefault() {
        let chosen: Int
        if let existing = profiles.firstIndex(where: {
            $0.isUniversalDefault == true && $0.applicationBundleID == nil
        }) {
            chosen = existing
        } else if let unbound = profiles.firstIndex(where: { $0.applicationBundleID == nil }) {
            chosen = unbound
        } else {
            var profile = G13Profile(name: "Default (All Apps)")
            profile.isUniversalDefault = true
            profiles.insert(profile, at: 0)
            activeProfileIndex += 1
            chosen = 0
        }
        for index in profiles.indices {
            profiles[index].isUniversalDefault = index == chosen
        }
    }

    var activeRawKeyMapping: [String: String] {
        guard let profile = activeProfile else { return [:] }
        return rawKeyMapping(for: profile)
    }

    var outputRawKeyMapping: [String: String] {
        guard let profile = outputProfile else { return [:] }
        return rawKeyMapping(for: profile)
    }

    private func rawKeyMapping(for profile: G13Profile) -> [String: String] {
        switch activeLayer {
        case 2: return profile.m2KeyMapping ?? [:]
        case 3: return profile.m3KeyMapping ?? [:]
        default: return profile.keyMapping
        }
    }

    private func rawJoystickMapping(for profile: G13Profile) -> [String: String] {
        switch activeLayer {
        case 2: return profile.m2JoystickMapping ?? [:]
        case 3: return profile.m3JoystickMapping ?? [:]
        default: return profile.joystickMapping
        }
    }

    // Computed accessors for the active profile's properties.
    // These allow the rest of the app to work with KeyAction dictionaries
    // without knowing about the profile system internals.
    var keyMapping: [String: KeyAction] {
        parsedMapping(activeRawKeyMapping, profile: activeProfile)
    }

    var outputKeyMapping: [String: KeyAction] {
        parsedMapping(outputRawKeyMapping, profile: outputProfile)
    }

    private func parsedMapping(_ mapping: [String: String], profile: G13Profile?) -> [String: KeyAction] {
        var result: [String: KeyAction] = [:]
        for (key, value) in mapping {
            let raw: String
            if value.hasPrefix("@") {
                guard let command = command(for: value, in: profile), command.kind == .keystroke,
                      let first = command.steps.first else { continue }
                raw = first
            } else {
                raw = value
            }
            if let action = KeyAction.parse(raw) {
                result[key.uppercased()] = action
            }
        }
        return result
    }

    var joystickMapping: [String: KeyAction] {
        parsedMapping(activeProfile.map { rawJoystickMapping(for: $0) } ?? [:], profile: activeProfile)
    }

    var outputJoystickMapping: [String: KeyAction] {
        parsedMapping(outputProfile.map { rawJoystickMapping(for: $0) } ?? [:], profile: outputProfile)
    }

    var outputJoystickMode: G13JoystickMode {
        guard let profile = outputProfile else { return .keys }
        switch activeLayer {
        case 2: return profile.m2JoystickMode ?? .keys
        case 3: return profile.m3JoystickMode ?? .keys
        default: return profile.joystickMode ?? .keys
        }
    }

    var outputJoystickDeadzone: Int {
        min(max(outputProfile?.joystickDeadzone ?? 20, 0), 127)
    }

    var outputJoystickScrollSpeed: Int {
        min(max(outputProfile?.joystickScrollSpeed ?? 2, 1), 5)
    }

    var outputJoystickHorizontalScrollSpeed: Int {
        min(max(outputProfile?.joystickHorizontalScrollSpeed ?? outputProfile?.joystickScrollSpeed ?? 2, 1), 5)
    }

    var outputBacklightColor: G13BacklightColor {
        color(for: outputProfile ?? activeProfile, layer: activeLayer)
    }

    func backlightColor(for layer: Int) -> G13BacklightColor {
        color(for: activeProfile, layer: layer)
    }

    private func color(for profile: G13Profile?, layer: Int) -> G13BacklightColor {
        guard let profile else { return G13BacklightColor(red: 0, green: 80, blue: 255) }
        let base = G13BacklightColor(red: profile.backlightR,
                                     green: profile.backlightG,
                                     blue: profile.backlightB)
        switch layer {
        case 2: return profile.m2BacklightColor ?? base
        case 3: return profile.m3BacklightColor ?? base
        default: return base
        }
    }

    var backlightR: UInt8 {
        get { UInt8(backlightColor(for: activeLayer).red) }
        set {
            var color = backlightColor(for: activeLayer)
            color.red = Int(newValue)
            setBacklightColor(color)
        }
    }

    var backlightG: UInt8 {
        get { UInt8(backlightColor(for: activeLayer).green) }
        set {
            var color = backlightColor(for: activeLayer)
            color.green = Int(newValue)
            setBacklightColor(color)
        }
    }

    var backlightB: UInt8 {
        get { UInt8(backlightColor(for: activeLayer).blue) }
        set {
            var color = backlightColor(for: activeLayer)
            color.blue = Int(newValue)
            setBacklightColor(color)
        }
    }

    func setBacklightColor(_ color: G13BacklightColor) {
        guard profiles.indices.contains(activeProfileIndex) else { return }
        let safe = G13BacklightColor(red: color.red, green: color.green, blue: color.blue)
        switch activeLayer {
        case 2: profiles[activeProfileIndex].m2BacklightColor = safe
        case 3: profiles[activeProfileIndex].m3BacklightColor = safe
        default:
            profiles[activeProfileIndex].backlightR = safe.red
            profiles[activeProfileIndex].backlightG = safe.green
            profiles[activeProfileIndex].backlightB = safe.blue
        }
        save()
    }

    var joystickDeadzone: Int {
        get { activeProfileIndex < profiles.count ? min(max(profiles[activeProfileIndex].joystickDeadzone, 0), 127) : 20 }
        set {
            if activeProfileIndex < profiles.count {
                beforeInputConfigurationChange?()
                profiles[activeProfileIndex].joystickDeadzone = min(max(newValue, 0), 127)
                save()
            }
        }
    }

    var activeProfileName: String {
        activeProfileIndex < profiles.count ? profiles[activeProfileIndex].name : "None"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Load

    func load() {
        if let folderData = defaults.data(forKey: "commandFolders"),
           let saved = try? JSONDecoder().decode([G13CommandFolder].self, from: folderData) {
            commandFolders = saved
        }
        if let commandData = defaults.data(forKey: "namedCommands"),
           let saved = try? JSONDecoder().decode([G13Command].self, from: commandData) {
            commands = saved
        }
        seedProToolsCommandsIfNeeded()
        seedFrontDuplicateIfNeeded()
        seedAdditionalProToolsCommandsIfNeeded()
        refineProToolsStarterIconsIfNeeded()
        organizeProToolsStartersIfNeeded()
        if let data = defaults.data(forKey: "profiles"),
           let decoded = try? JSONDecoder().decode([G13Profile].self, from: data),
           !decoded.isEmpty {
            profiles = decoded
            activeProfileIndex = defaults.integer(forKey: "activeProfileIndex")
            if activeProfileIndex < 0 || activeProfileIndex >= profiles.count { activeProfileIndex = 0 }
            activeLayer = min(max(defaults.integer(forKey: "activeLayer"), 1), 3)
            ensureUniversalDefault()
            startupProfileID = defaults.string(forKey: "startupProfileID")
                .flatMap(UUID.init(uuidString:))
            if let id = startupProfileID,
               let index = profiles.firstIndex(where: { $0.id == id }) {
                activeProfileIndex = index
            } else {
                // Preserve the previous version's last-selected startup behavior
                // until the user explicitly locks a profile with L3 or the UI.
                startupProfileID = profiles[activeProfileIndex].id
            }
            save()
            print("[ProfileManager] Loaded \(profiles.count) profiles, active: \(activeProfileName)")
        } else {
            // First launch or corrupted data: create defaults
            createDefaultProfiles()
            save()
            print("[ProfileManager] Created default profiles")
        }
    }

    func createDefaultProfiles() {
        var profile = G13Profile(name: "Default (All Apps)")
        profile.isUniversalDefault = true
        profiles = [profile]
        activeProfileIndex = 0
        startupProfileID = profile.id
    }

    // MARK: - Save

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: "profiles")
        }
        defaults.set(activeProfileIndex, forKey: "activeProfileIndex")
        defaults.set(activeLayer, forKey: "activeLayer")
        defaults.set(startupProfileID?.uuidString, forKey: "startupProfileID")
        if let commandData = try? JSONEncoder().encode(commands) {
            defaults.set(commandData, forKey: "namedCommands")
        }
        if let folderData = try? JSONEncoder().encode(commandFolders) {
            defaults.set(folderData, forKey: "commandFolders")
        }
    }

    // Restore a validated library in one update. Release generated keys first
    // so a held key cannot retain an assignment from the old library.
    func replaceLibrary(profiles restoredProfiles: [G13Profile],
                        commands restoredCommands: [G13Command],
                        folders restoredFolders: [G13CommandFolder] = [],
                        selectedProfileID: UUID, startupProfileID restoredStartupID: UUID? = nil,
                        layer: Int) {
        guard !restoredProfiles.isEmpty else { return }
        beforeInputConfigurationChange?()
        profiles = restoredProfiles
        commands = restoredCommands
        commandFolders = restoredFolders
        activeProfileIndex = restoredProfiles.firstIndex { $0.id == selectedProfileID } ?? 0
        activeLayer = min(max(layer, 1), 3)
        inputSuppressed = false
        manualOutputProfileID = nil
        ensureUniversalDefault()
        let preferredStartupID = restoredStartupID ?? selectedProfileID
        startupProfileID = profiles.contains(where: { $0.id == preferredStartupID }) ?
            preferredStartupID : profiles[universalDefaultIndex ?? 0].id
        save()
        onSelectionChanged?()
    }

    private func seedProToolsCommandsIfNeeded() {
        guard !defaults.bool(forKey: "proToolsCommandLibrarySeeded") else { return }
        let presets: [(String, String, String)] = [
            ("Zoom Out", "CMD+[", "minus.magnifyingglass"),
            ("Zoom In", "CMD+]", "plus.magnifyingglass"),
            ("Record Enable", "NUMPAD3", "record.circle"),
            ("Play / Stop", "SPACE", "playpause.fill"),
            ("Save Session", "CMD+S", "square.and.arrow.down"),
            ("Save Session As", "CMD+CTRL+S", "studio:save-as"),
            ("New Track", "CMD+SHIFT+N", "plus.rectangle.on.rectangle"),
            ("Separate Clip", "CMD+E", "scissors"),
            ("Duplicate Selection", "CMD+D", "square.on.square"),
            ("Shuffle Mode", "F1", "shuffle"),
            ("Slip Mode", "F2", "arrow.left.and.right"),
            ("Spot Mode", "F3", "scope"),
            ("Grid Mode", "F4", "square.grid.3x3"),
            ("Trim Tool", "F6", "crop"),
            ("Selector Tool", "F7", "cursorarrow"),
            ("Grabber Tool", "F8", "hand.point.up.left.fill"),
            ("Smart Tool", "CMD+7", "hammer.fill")
        ]
        for (name, shortcut, symbol) in presets {
            var command = G13Command(name: name, kind: .keystroke, steps: [shortcut])
            command.applicationBundleID = "com.avid.protools"
            command.iconReference = symbol.hasPrefix("studio:") ? symbol : "sf:" + symbol
            commands.append(command)
        }
        defaults.set(true, forKey: "proToolsCommandLibrarySeeded")
    }

    private func seedFrontDuplicateIfNeeded() {
        guard !defaults.bool(forKey: "frontDuplicateCommandSeeded") else { return }
        var command = G13Command(name: "Duplicate in Front", kind: .keystroke,
                                 steps: ["CTRL+ALT+K"])
        command.applicationBundleID = "com.avid.protools"
        command.iconReference = "studio:duplicate-front"
        commands.append(command)
        defaults.set(true, forKey: "frontDuplicateCommandSeeded")
    }

    private func seedAdditionalProToolsCommandsIfNeeded() {
        guard !defaults.bool(forKey: "proToolsAdditionalCommandsSeeded") else { return }
        let presets: [(String, String, String)] = [
            ("Stop Recording (Keep Take)", "SPACE", "stop.fill"),
            ("Stop & Discard Take", "CMD+PERIOD", "trash.fill"),
            ("Undo", "CMD+Z", "arrow.uturn.backward"),
            ("Redo", "CMD+SHIFT+Z", "arrow.uturn.forward"),
            ("Session Start", "RETURN", "backward.end.fill"),
            ("Session End", "ALT+RETURN", "forward.end.fill"),
            ("Nudge Left", "NUMPADMINUS", "arrow.left"),
            ("Nudge Right", "NUMPADPLUS", "arrow.right"),
            ("Consolidate Clip", "ALT+SHIFT+3", "square.stack.3d.up.fill"),
            ("Toggle Clip Gain Info", "CTRL+SHIFT+EQUAL", "info.circle"),
            ("Toggle Clip Gain Line", "CTRL+SHIFT+MINUS", "waveform.path"),
            ("Lock / Unlock Clips", "CMD+L", "lock.fill"),
            ("Decrease Clip Gain", "CTRL+SHIFT+DOWN", "arrow.down"),
            ("Increase Clip Gain", "CTRL+SHIFT+UP", "arrow.up")
        ]
        for (name, shortcut, symbol) in presets {
            var command = G13Command(name: name, kind: .keystroke, steps: [shortcut])
            command.applicationBundleID = "com.avid.protools"
            command.iconReference = "sf:" + symbol
            commands.append(command)
        }
        defaults.set(true, forKey: "proToolsAdditionalCommandsSeeded")
    }

    private func refineProToolsStarterIconsIfNeeded() {
        guard !defaults.bool(forKey: "proToolsStarterIconsRefinedV12") else { return }
        let replacements: [String: (old: String, new: String)] = [
            "Zoom Out": ("sf:magnifyingglass", "sf:minus.magnifyingglass"),
            "Zoom In": ("sf:magnifyingglass", "sf:plus.magnifyingglass"),
            "Save Session As": ("sf:square.and.arrow.down", "studio:save-as"),
            "Duplicate in Front": ("sf:square.on.square", "studio:duplicate-front")
        ]
        for index in commands.indices {
            guard commands[index].applicationBundleID?.lowercased() == "com.avid.protools",
                  let replacement = replacements[commands[index].name],
                  commands[index].iconReference == replacement.old else { continue }
            commands[index].iconReference = replacement.new
        }
        defaults.set(true, forKey: "proToolsStarterIconsRefinedV12")
    }

    private func organizeProToolsStartersIfNeeded() {
        guard !defaults.bool(forKey: "proToolsStarterFoldersV14") else { return }
        let groups: [(String, [String])] = [
            ("Transport", ["Record Enable", "Play / Stop", "Stop Recording (Keep Take)",
                            "Stop & Discard Take", "Session Start", "Session End"]),
            ("Session", ["Save Session", "Save Session As", "New Track"]),
            ("Editing", ["Separate Clip", "Duplicate Selection", "Duplicate in Front",
                          "Consolidate Clip", "Lock / Unlock Clips", "Undo", "Redo",
                          "Toggle Clip Gain Info", "Toggle Clip Gain Line",
                          "Decrease Clip Gain", "Increase Clip Gain"]),
            ("Navigation", ["Zoom In", "Zoom Out", "Nudge Left", "Nudge Right"]),
            ("Modes & Tools", ["Shuffle Mode", "Spot Mode", "Slip Mode", "Grid Mode",
                                "Trim Tool", "Selector Tool", "Grabber Tool", "Smart Tool"])
        ]
        let bundleID = "com.avid.protools"
        for (name, commandNames) in groups {
            let folder: G13CommandFolder
            if let existing = folders(for: bundleID).first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                folder = existing
            } else {
                folder = G13CommandFolder(name: name, applicationBundleID: bundleID)
                commandFolders.append(folder)
            }
            let names = Set(commandNames)
            for index in commands.indices where commands[index].applicationBundleID?.lowercased() == bundleID &&
                commands[index].folderID == nil && names.contains(commands[index].name) {
                commands[index].folderID = folder.id
            }
        }
        defaults.set(true, forKey: "proToolsStarterFoldersV14")
    }

    func commandsVisibleInActiveProfile() -> [G13Command] {
        let bundleID = activeProfile?.applicationBundleID?.lowercased()
        return commands.filter { command in
            command.applicationBundleID == nil || command.applicationBundleID?.lowercased() == bundleID
        }
    }

    func folders(for bundleID: String?) -> [G13CommandFolder] {
        commandFolders.filter { $0.applicationBundleID?.lowercased() == bundleID?.lowercased() }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func addCommandFolder(name: String, applicationBundleID: String?) -> G13CommandFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80,
              !folders(for: applicationBundleID).contains(where: {
                  $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
              }) else { return nil }
        let folder = G13CommandFolder(name: trimmed, applicationBundleID: applicationBundleID)
        commandFolders.append(folder)
        save()
        return folder
    }

    func renameCommandFolder(_ id: UUID, to name: String) -> Bool {
        guard let index = commandFolders.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80,
              !folders(for: commandFolders[index].applicationBundleID).contains(where: {
                  $0.id != id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
              }) else { return false }
        commandFolders[index].name = trimmed
        save()
        return true
    }

    func deleteCommandFolder(_ id: UUID) {
        guard commandFolders.contains(where: { $0.id == id }) else { return }
        commandFolders.removeAll { $0.id == id }
        for index in commands.indices where commands[index].folderID == id {
            commands[index].folderID = nil
        }
        save()
    }

    @discardableResult
    func moveCommand(_ assignment: String, toFolder folderID: UUID) -> Bool {
        guard let folder = commandFolders.first(where: { $0.id == folderID }),
              let index = commands.firstIndex(where: { $0.assignment == assignment }),
              commands[index].applicationBundleID?.lowercased() == folder.applicationBundleID?.lowercased(),
              commandsVisibleInActiveProfile().contains(where: { $0.id == commands[index].id }) else {
            return false
        }
        guard commands[index].folderID != folderID else { return true }
        commands[index].folderID = folderID
        save()
        return true
    }

    @discardableResult
    func assignVisibleCommand(_ assignment: String, to control: String,
                              isJoystick: Bool) -> Bool {
        guard let command = commandsVisibleInActiveProfile().first(where: {
            $0.assignment == assignment
        }), !isJoystick || command.kind == .keystroke else { return false }
        if isJoystick { setJoystickDirection(control, to: command.assignment) }
        else { setKey(control, to: command.assignment) }
        return true
    }

    // MARK: - Profile management

    func addProfile(name: String) {
        var profile = G13Profile(name: name)
        // Copy current profile's settings as a starting point
        if activeProfileIndex < profiles.count {
            let current = profiles[activeProfileIndex]
            profile.keyMapping = current.keyMapping
            profile.joystickMapping = current.joystickMapping
            profile.m2KeyMapping = current.m2KeyMapping
            profile.m3KeyMapping = current.m3KeyMapping
            profile.m2JoystickMapping = current.m2JoystickMapping
            profile.m3JoystickMapping = current.m3JoystickMapping
            profile.m2BacklightColor = current.m2BacklightColor
            profile.m3BacklightColor = current.m3BacklightColor
            profile.keyIcons = current.keyIcons
            profile.m2KeyIcons = current.m2KeyIcons
            profile.m3KeyIcons = current.m3KeyIcons
            profile.keyIconColors = current.keyIconColors
            profile.m2KeyIconColors = current.m2KeyIconColors
            profile.m3KeyIconColors = current.m3KeyIconColors
            profile.joystickMode = current.joystickMode
            profile.m2JoystickMode = current.m2JoystickMode
            profile.m3JoystickMode = current.m3JoystickMode
            profile.joystickScrollSpeed = current.joystickScrollSpeed
            profile.joystickHorizontalScrollSpeed = current.joystickHorizontalScrollSpeed
            profile.backlightR = current.backlightR
            profile.backlightG = current.backlightG
            profile.backlightB = current.backlightB
            profile.joystickDeadzone = current.joystickDeadzone
        }
        profiles.append(profile)
        save()
        onSelectionChanged?()
    }

    @discardableResult
    func duplicateActiveProfile() -> Int? {
        guard let source = activeProfile else { return nil }
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " Copy"
        copy.applicationBundleID = nil
        copy.applicationDisplayName = nil
        copy.isUniversalDefault = false
        copy.autoSwitch = false
        beforeInputConfigurationChange?()
        profiles.append(copy)
        activeProfileIndex = profiles.count - 1
        activeLayer = 1
        inputSuppressed = false
        manualOutputProfileID = copy.id
        save()
        onSelectionChanged?()
        return activeProfileIndex
    }

    func deleteProfile(at index: Int) {
        guard profiles.count > 1, index >= 0, index < profiles.count,
              profiles[index].isUniversalDefault != true else { return }
        beforeInputConfigurationChange?()
        let removedID = profiles[index].id
        profiles.remove(at: index)
        if startupProfileID == removedID {
            startupProfileID = profiles[universalDefaultIndex ?? 0].id
        }
        if manualOutputProfileID == removedID { manualOutputProfileID = nil }
        if index < activeProfileIndex { activeProfileIndex -= 1 }
        if activeProfileIndex >= profiles.count {
            activeProfileIndex = profiles.count - 1
        }
        inputSuppressed = false
        save()
        onSelectionChanged?()
    }

    func renameProfile(at index: Int, to newName: String) {
        guard index >= 0, index < profiles.count else { return }
        profiles[index].name = newName
        save()
        if index == activeProfileIndex || profiles[index].id == startupProfileID {
            onSelectionChanged?()
        }
    }

    func switchToProfile(at index: Int, manual: Bool = true) {
        guard index >= 0, index < profiles.count else { return }
        if manual { manualOutputProfileID = profiles[index].id }
        if index == activeProfileIndex {
            inputSuppressed = false
            objectWillChange.send()
            onSelectionChanged?()
            return
        }
        beforeInputConfigurationChange?()
        activeProfileIndex = index
        activeLayer = 1
        inputSuppressed = false
        save()
        objectWillChange.send()
        onSelectionChanged?()
        print("[ProfileManager] Switched to profile: \(activeProfileName)")
    }

    // MARK: - Key mapping (on active profile)

    func setKey(_ g13Key: String, to macKey: String) {
        guard activeProfileIndex < profiles.count else { return }
        beforeInputConfigurationChange?()
        let key = g13Key.uppercased()
        if activeRawKeyMapping[key] != macKey {
            removeIconOverride(for: key, isJoystick: false)
        }
        switch activeLayer {
        case 2: profiles[activeProfileIndex].m2KeyMapping = (profiles[activeProfileIndex].m2KeyMapping ?? [:]).merging([key: macKey]) { _, new in new }
        case 3: profiles[activeProfileIndex].m3KeyMapping = (profiles[activeProfileIndex].m3KeyMapping ?? [:]).merging([key: macKey]) { _, new in new }
        default: profiles[activeProfileIndex].keyMapping[key] = macKey
        }
        save()
        objectWillChange.send()
    }

    func clearKey(_ g13Key: String) {
        guard activeProfileIndex < profiles.count else { return }
        beforeInputConfigurationChange?()
        let key = g13Key.uppercased()
        removeIconOverride(for: key, isJoystick: false)
        switch activeLayer {
        case 2: profiles[activeProfileIndex].m2KeyMapping?.removeValue(forKey: key)
        case 3: profiles[activeProfileIndex].m3KeyMapping?.removeValue(forKey: key)
        default: profiles[activeProfileIndex].keyMapping.removeValue(forKey: key)
        }
        save()
        objectWillChange.send()
    }

    func setJoystickDirection(_ direction: String, to macKey: String) {
        guard activeProfileIndex < profiles.count else { return }
        beforeInputConfigurationChange?()
        let key = direction.uppercased()
        let old = activeProfile.map { rawJoystickMapping(for: $0)[key] } ?? nil
        if old != macKey { removeIconOverride(for: key, isJoystick: true) }
        switch activeLayer {
        case 2: profiles[activeProfileIndex].m2JoystickMapping = (profiles[activeProfileIndex].m2JoystickMapping ?? [:]).merging([key: macKey]) { _, new in new }
        case 3: profiles[activeProfileIndex].m3JoystickMapping = (profiles[activeProfileIndex].m3JoystickMapping ?? [:]).merging([key: macKey]) { _, new in new }
        default: profiles[activeProfileIndex].joystickMapping[key] = macKey
        }
        save()
        objectWillChange.send()
    }

    func clearJoystickDirection(_ direction: String) {
        guard activeProfileIndex < profiles.count else { return }
        beforeInputConfigurationChange?()
        let key = direction.uppercased()
        removeIconOverride(for: key, isJoystick: true)
        switch activeLayer {
        case 2: profiles[activeProfileIndex].m2JoystickMapping?.removeValue(forKey: key)
        case 3: profiles[activeProfileIndex].m3JoystickMapping?.removeValue(forKey: key)
        default: profiles[activeProfileIndex].joystickMapping.removeValue(forKey: key)
        }
        save()
        objectWillChange.send()
    }

    // Reset the active profile to defaults
    func resetActiveProfile() {
        guard activeProfileIndex < profiles.count else { return }
        beforeInputConfigurationChange?()
        let name = profiles[activeProfileIndex].name
        let bundleID = profiles[activeProfileIndex].applicationBundleID
        let displayName = profiles[activeProfileIndex].applicationDisplayName
        let isUniversal = profiles[activeProfileIndex].isUniversalDefault
        let autoSwitch = profiles[activeProfileIndex].autoSwitch
        profiles[activeProfileIndex] = G13Profile.defaultGaming()
        profiles[activeProfileIndex].name = name
        profiles[activeProfileIndex].applicationBundleID = bundleID
        profiles[activeProfileIndex].applicationDisplayName = displayName
        profiles[activeProfileIndex].isUniversalDefault = isUniversal
        profiles[activeProfileIndex].autoSwitch = autoSwitch
        save()
        objectWillChange.send()
    }

    func switchLayer(_ layer: Int) {
        guard (1...3).contains(layer), activeLayer != layer else { return }
        beforeInputConfigurationChange?()
        activeLayer = layer
        save()
        onSelectionChanged?()
    }

    func bindActiveProfile(to bundleID: String?, displayName: String? = nil) {
        guard profiles.indices.contains(activeProfileIndex) else { return }
        guard !activeProfileIsUniversal || bundleID == nil else { return }
        if profiles[activeProfileIndex].applicationBundleID != bundleID {
            beforeInputConfigurationChange?()
        }
        profiles[activeProfileIndex].applicationBundleID = bundleID
        profiles[activeProfileIndex].applicationDisplayName = bundleID == nil ? nil : displayName
        profiles[activeProfileIndex].autoSwitch = bundleID != nil
        save()
    }

    func activateProfile(for bundleID: String) {
        let applicationChanged = frontmostBundleID?.caseInsensitiveCompare(bundleID) != .orderedSame
        if applicationChanged || editorIsFrontmost {
            beforeInputConfigurationChange?()
            editorIsFrontmost = false
            frontmostBundleID = bundleID
        }
        if applicationChanged { manualOutputProfileID = nil }
        if let match = profiles.firstIndex(where: {
            $0.applicationBundleID?.lowercased() == bundleID.lowercased() && $0.autoSwitch != false
        }), manualOutputProfileID == nil {
            if match == activeProfileIndex { onSelectionChanged?() }
            else { switchToProfile(at: match, manual: false) }
        } else {
            onSelectionChanged?()
        }
    }

    func command(for assignment: String) -> G13Command? {
        command(for: assignment, in: activeProfile)
    }

    func outputCommand(for assignment: String) -> G13Command? {
        command(for: assignment, in: outputProfile)
    }

    private func command(for assignment: String, in profile: G13Profile?) -> G13Command? {
        guard assignment.hasPrefix("@") else { return nil }
        return commands.first {
            $0.id.uuidString == String(assignment.dropFirst()) &&
            ($0.applicationBundleID == nil ||
             $0.applicationBundleID?.lowercased() == profile?.applicationBundleID?.lowercased())
        }
    }

    private func iconKey(_ key: String, isJoystick: Bool) -> String {
        (isJoystick ? "joy:" : "key:") + key.uppercased()
    }

    private func removeIconOverride(for key: String, isJoystick: Bool) {
        let id = iconKey(key, isJoystick: isJoystick)
        switch activeLayer {
        case 2: profiles[activeProfileIndex].m2KeyIcons?.removeValue(forKey: id)
        case 3: profiles[activeProfileIndex].m3KeyIcons?.removeValue(forKey: id)
        default: profiles[activeProfileIndex].keyIcons?.removeValue(forKey: id)
        }
        switch activeLayer {
        case 2: profiles[activeProfileIndex].m2KeyIconColors?.removeValue(forKey: id)
        case 3: profiles[activeProfileIndex].m3KeyIconColors?.removeValue(forKey: id)
        default: profiles[activeProfileIndex].keyIconColors?.removeValue(forKey: id)
        }
    }

    func iconColor(for key: String, isJoystick: Bool) -> String? {
        guard let profile = activeProfile else { return nil }
        let id = iconKey(key, isJoystick: isJoystick)
        switch activeLayer {
        case 2: return profile.m2KeyIconColors?[id]
        case 3: return profile.m3KeyIconColors?[id]
        default: return profile.keyIconColors?[id]
        }
    }

    func setIconColor(_ color: String?, for key: String, isJoystick: Bool) {
        guard profiles.indices.contains(activeProfileIndex) else { return }
        let id = iconKey(key, isJoystick: isJoystick)
        switch activeLayer {
        case 2:
            var values = profiles[activeProfileIndex].m2KeyIconColors ?? [:]
            values[id] = color
            profiles[activeProfileIndex].m2KeyIconColors = values
        case 3:
            var values = profiles[activeProfileIndex].m3KeyIconColors ?? [:]
            values[id] = color
            profiles[activeProfileIndex].m3KeyIconColors = values
        default:
            var values = profiles[activeProfileIndex].keyIconColors ?? [:]
            values[id] = color
            profiles[activeProfileIndex].keyIconColors = values
        }
        save()
    }

    func clearAllIconColorOverrides() {
        for index in profiles.indices {
            profiles[index].keyIconColors = [:]
            profiles[index].m2KeyIconColors = [:]
            profiles[index].m3KeyIconColors = [:]
        }
        for index in commands.indices { commands[index].iconColor = nil }
        save()
    }

    func iconReference(for key: String, isJoystick: Bool) -> String? {
        guard let profile = activeProfile else { return nil }
        let id = iconKey(key, isJoystick: isJoystick)
        switch activeLayer {
        case 2: return profile.m2KeyIcons?[id]
        case 3: return profile.m3KeyIcons?[id]
        default: return profile.keyIcons?[id]
        }
    }

    func setIconReference(_ reference: String?, for key: String, isJoystick: Bool) {
        guard profiles.indices.contains(activeProfileIndex) else { return }
        let id = iconKey(key, isJoystick: isJoystick)
        switch activeLayer {
        case 2:
            var icons = profiles[activeProfileIndex].m2KeyIcons ?? [:]
            icons[id] = reference
            profiles[activeProfileIndex].m2KeyIcons = icons
        case 3:
            var icons = profiles[activeProfileIndex].m3KeyIcons ?? [:]
            icons[id] = reference
            profiles[activeProfileIndex].m3KeyIcons = icons
        default:
            var icons = profiles[activeProfileIndex].keyIcons ?? [:]
            icons[id] = reference
            profiles[activeProfileIndex].keyIcons = icons
        }
        save()
    }

    func saveCommand(_ command: G13Command) {
        guard !command.name.trimmingCharacters(in: .whitespaces).isEmpty,
              command.isValidAction,
              command.folderID.map({ id in commandFolders.contains(where: {
                  $0.id == id && $0.applicationBundleID?.lowercased() == command.applicationBundleID?.lowercased()
              }) }) ?? true else { return }
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            if commands[index].steps != command.steps ||
               commands[index].kind != command.kind ||
               commands[index].mouseAction != command.mouseAction ||
               commands[index].mouseModifiers != command.mouseModifiers ||
               commands[index].holdMilliseconds != command.holdMilliseconds ||
               commands[index].applicationBundleID?.lowercased() != command.applicationBundleID?.lowercased() {
                beforeInputConfigurationChange?()
            }
            commands[index] = command
        } else {
            commands.append(command)
        }
        save()
    }

    func deleteCommand(_ command: G13Command) {
        beforeInputConfigurationChange?()
        commands.removeAll { $0.id == command.id }
        for index in profiles.indices {
            for key in profiles[index].keyMapping.keys where profiles[index].keyMapping[key] == command.assignment {
                profiles[index].keyIcons?.removeValue(forKey: iconKey(key, isJoystick: false))
            }
            for key in profiles[index].m2KeyMapping?.keys ?? Dictionary<String, String>().keys
                where profiles[index].m2KeyMapping?[key] == command.assignment {
                profiles[index].m2KeyIcons?.removeValue(forKey: iconKey(key, isJoystick: false))
            }
            for key in profiles[index].m3KeyMapping?.keys ?? Dictionary<String, String>().keys
                where profiles[index].m3KeyMapping?[key] == command.assignment {
                profiles[index].m3KeyIcons?.removeValue(forKey: iconKey(key, isJoystick: false))
            }
            for key in profiles[index].joystickMapping.keys where profiles[index].joystickMapping[key] == command.assignment {
                profiles[index].keyIcons?.removeValue(forKey: iconKey(key, isJoystick: true))
            }
            for key in profiles[index].m2JoystickMapping?.keys ?? Dictionary<String, String>().keys
                where profiles[index].m2JoystickMapping?[key] == command.assignment {
                profiles[index].m2KeyIcons?.removeValue(forKey: iconKey(key, isJoystick: true))
            }
            for key in profiles[index].m3JoystickMapping?.keys ?? Dictionary<String, String>().keys
                where profiles[index].m3JoystickMapping?[key] == command.assignment {
                profiles[index].m3KeyIcons?.removeValue(forKey: iconKey(key, isJoystick: true))
            }
            profiles[index].keyMapping = profiles[index].keyMapping.filter { $0.value != command.assignment }
            profiles[index].m2KeyMapping = profiles[index].m2KeyMapping?.filter { $0.value != command.assignment }
            profiles[index].m3KeyMapping = profiles[index].m3KeyMapping?.filter { $0.value != command.assignment }
            profiles[index].joystickMapping = profiles[index].joystickMapping.filter { $0.value != command.assignment }
            profiles[index].m2JoystickMapping = profiles[index].m2JoystickMapping?.filter { $0.value != command.assignment }
            profiles[index].m3JoystickMapping = profiles[index].m3JoystickMapping?.filter { $0.value != command.assignment }
        }
        save()
    }
}

struct G13Command: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case keystroke, multiKey, mouseFunction }
    var id = UUID()
    var name: String
    var kind: Kind
    var steps: [String]
    var mouseAction: G13MouseAction?
    var mouseModifiers: [G13MouseModifier]?
    var delayMilliseconds: Int = 50
    var iconReference: String?
    var iconColor: String?
    var holdMilliseconds: Int?
    var applicationBundleID: String?
    var folderID: UUID?
    var assignment: String { "@" + id.uuidString }
    var isValidAction: Bool {
        switch kind {
        case .keystroke: return steps.count == 1 && KeyAction.parse(steps[0]) != nil &&
            (holdMilliseconds.map { (100...30_000).contains($0) } ?? true)
        case .multiKey: return holdMilliseconds == nil && (1...16).contains(steps.count) &&
            steps.allSatisfy { KeyAction.parse($0) != nil }
        case .mouseFunction: return holdMilliseconds == nil && mouseAction != nil && steps.isEmpty
        }
    }
    var actionDescription: String {
        switch kind {
        case .keystroke:
            let shortcut = steps.first ?? "No key"
            return holdMilliseconds.map { "\(shortcut) · Hold \(Double($0) / 1000) s" } ?? shortcut
        case .multiKey: return "\(steps.count) steps"
        case .mouseFunction:
            let modifiers = G13MouseModifier.allCases.filter { mouseModifiers?.contains($0) == true }
            return (modifiers.map(\.label) + [mouseAction?.label ?? "Mouse action"]).joined(separator: " + ")
        }
    }
}

struct G13CommandFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var applicationBundleID: String?
}
