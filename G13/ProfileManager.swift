// =============================================================
//  ProfileManager.swift
//  Multi-profile preferences management via UserDefaults
// =============================================================

import Foundation
import Combine

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

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.keyMapping = [:]
        self.joystickMapping = [:]
        self.backlightR = 0
        self.backlightG = 80
        self.backlightB = 255
        self.joystickDeadzone = 20
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

    private let defaults = UserDefaults.standard

    // Computed accessors for the active profile's properties.
    // These allow the rest of the app to work with KeyAction dictionaries
    // without knowing about the profile system internals.
    var keyMapping: [String: KeyAction] {
        guard activeProfileIndex < profiles.count else { return [:] }
        var result: [String: KeyAction] = [:]
        for (key, value) in profiles[activeProfileIndex].keyMapping {
            if let action = KeyAction.parse(value) {
                result[key.uppercased()] = action
            }
        }
        return result
    }

    var joystickMapping: [String: KeyAction] {
        guard activeProfileIndex < profiles.count else { return [:] }
        var result: [String: KeyAction] = [:]
        for (dir, value) in profiles[activeProfileIndex].joystickMapping {
            if !value.isEmpty, let action = KeyAction.parse(value) {
                result[dir.uppercased()] = action
            }
        }
        return result
    }

    var backlightR: UInt8 {
        get { activeProfileIndex < profiles.count ? UInt8(min(profiles[activeProfileIndex].backlightR, 255)) : 0 }
        set { if activeProfileIndex < profiles.count { profiles[activeProfileIndex].backlightR = Int(newValue); save() } }
    }

    var backlightG: UInt8 {
        get { activeProfileIndex < profiles.count ? UInt8(min(profiles[activeProfileIndex].backlightG, 255)) : 80 }
        set { if activeProfileIndex < profiles.count { profiles[activeProfileIndex].backlightG = Int(newValue); save() } }
    }

    var backlightB: UInt8 {
        get { activeProfileIndex < profiles.count ? UInt8(min(profiles[activeProfileIndex].backlightB, 255)) : 255 }
        set { if activeProfileIndex < profiles.count { profiles[activeProfileIndex].backlightB = Int(newValue); save() } }
    }

    var joystickDeadzone: Int {
        get { activeProfileIndex < profiles.count ? profiles[activeProfileIndex].joystickDeadzone : 20 }
        set { if activeProfileIndex < profiles.count { profiles[activeProfileIndex].joystickDeadzone = newValue; save() } }
    }

    var activeProfileName: String {
        activeProfileIndex < profiles.count ? profiles[activeProfileIndex].name : "None"
    }

    init() {
        load()
    }

    // MARK: - Load

    func load() {
        if let data = defaults.data(forKey: "profiles"),
           let decoded = try? JSONDecoder().decode([G13Profile].self, from: data) {
            profiles = decoded
            activeProfileIndex = defaults.integer(forKey: "activeProfileIndex")
            if activeProfileIndex >= profiles.count { activeProfileIndex = 0 }
            print("[ProfileManager] Loaded \(profiles.count) profiles, active: \(activeProfileName)")
        } else {
            // First launch or corrupted data: create defaults
            createDefaultProfiles()
            save()
            print("[ProfileManager] Created default profiles")
        }
    }

    func createDefaultProfiles() {
        profiles = [
            G13Profile.defaultGaming(),
        ]
        activeProfileIndex = 0
    }

    // MARK: - Save

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: "profiles")
        }
        defaults.set(activeProfileIndex, forKey: "activeProfileIndex")
    }

    // MARK: - Profile management

    func addProfile(name: String) {
        var profile = G13Profile(name: name)
        // Copy current profile's settings as a starting point
        if activeProfileIndex < profiles.count {
            let current = profiles[activeProfileIndex]
            profile.keyMapping = current.keyMapping
            profile.joystickMapping = current.joystickMapping
            profile.backlightR = current.backlightR
            profile.backlightG = current.backlightG
            profile.backlightB = current.backlightB
            profile.joystickDeadzone = current.joystickDeadzone
        }
        profiles.append(profile)
        save()
    }

    func deleteProfile(at index: Int) {
        guard profiles.count > 1 else { return }  // Keep at least one profile
        profiles.remove(at: index)
        if activeProfileIndex >= profiles.count {
            activeProfileIndex = profiles.count - 1
        }
        save()
    }

    func renameProfile(at index: Int, to newName: String) {
        guard index < profiles.count else { return }
        profiles[index].name = newName
        save()
    }

    func switchToProfile(at index: Int) {
        guard index < profiles.count else { return }
        activeProfileIndex = index
        save()
        objectWillChange.send()
        print("[ProfileManager] Switched to profile: \(activeProfileName)")
    }

    // MARK: - Key mapping (on active profile)

    func setKey(_ g13Key: String, to macKey: String) {
        guard activeProfileIndex < profiles.count else { return }
        profiles[activeProfileIndex].keyMapping[g13Key.uppercased()] = macKey
        save()
        objectWillChange.send()
    }

    func clearKey(_ g13Key: String) {
        guard activeProfileIndex < profiles.count else { return }
        profiles[activeProfileIndex].keyMapping.removeValue(forKey: g13Key.uppercased())
        save()
        objectWillChange.send()
    }

    func setJoystickDirection(_ direction: String, to macKey: String) {
        guard activeProfileIndex < profiles.count else { return }
        profiles[activeProfileIndex].joystickMapping[direction.uppercased()] = macKey
        save()
        objectWillChange.send()
    }

    func clearJoystickDirection(_ direction: String) {
        guard activeProfileIndex < profiles.count else { return }
        profiles[activeProfileIndex].joystickMapping.removeValue(forKey: direction.uppercased())
        save()
        objectWillChange.send()
    }

    // Reset the active profile to defaults
    func resetActiveProfile() {
        guard activeProfileIndex < profiles.count else { return }
        let name = profiles[activeProfileIndex].name
        profiles[activeProfileIndex] = G13Profile.defaultGaming()
        profiles[activeProfileIndex].name = name
        save()
        objectWillChange.send()
    }
}
