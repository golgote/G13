import Foundation

enum G13BackupError: LocalizedError {
    case invalidFile
    case unsupportedVersion
    case invalidLibrary(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "This is not a valid G13 Studio backup, or the file is too large."
        case .unsupportedVersion: return "This backup was made by a newer version of G13 Studio."
        case .invalidLibrary(let reason): return "The backup cannot be restored: \(reason)"
        }
    }
}

struct G13ProfileBackup: Codable {
    let formatVersion: Int
    var profiles: [G13Profile]
    var commands: [G13Command]
    var commandFolders: [G13CommandFolder]? = nil
    let selectedProfileID: UUID
    var startupProfileID: UUID? = nil
    let activeLayer: Int
    let customIcons: [String: Data]

    static let maximumFileSize = 30_000_000

    static func create(from manager: ProfileManager) throws -> Data {
        guard let selectedID = manager.activeProfile?.id else {
            throw G13BackupError.invalidLibrary("There is no selected profile.")
        }
        let references = allIconReferences(profiles: manager.profiles, commands: manager.commands)
        var icons: [String: Data] = [:]
        for reference in references where reference.hasPrefix("custom:") {
            icons[reference] = try G13IconStore.backupData(for: reference)
        }
        var archive = G13ProfileBackup(formatVersion: 1, profiles: manager.profiles,
                                       commands: manager.commands,
                                       selectedProfileID: selectedID,
                                       activeLayer: manager.activeLayer,
                                       customIcons: icons)
        archive.commandFolders = manager.commandFolders
        archive.startupProfileID = manager.startupProfileID
        try archive.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maximumFileSize else { throw G13BackupError.invalidFile }
        return data
    }

    static func read(_ data: Data) throws -> G13ProfileBackup {
        guard data.count <= maximumFileSize else { throw G13BackupError.invalidFile }
        let archive: G13ProfileBackup
        do { archive = try JSONDecoder().decode(G13ProfileBackup.self, from: data) }
        catch { throw G13BackupError.invalidFile }
        try archive.validate()
        return archive
    }

    func restore(into manager: ProfileManager) throws {
        try validate()
        var remapped: [String: String] = [:]
        for reference in customIcons.keys.sorted() {
            guard let data = customIcons[reference] else { continue }
            remapped[reference] = try G13IconStore.restoreBackupData(data)
        }
        let restoredProfiles = profiles.map { profile -> G13Profile in
            var copy = profile
            copy.keyIcons = remap(profile.keyIcons, using: remapped)
            copy.m2KeyIcons = remap(profile.m2KeyIcons, using: remapped)
            copy.m3KeyIcons = remap(profile.m3KeyIcons, using: remapped)
            return copy
        }
        let restoredCommands = commands.map { command -> G13Command in
            var copy = command
            if let reference = command.iconReference {
                copy.iconReference = remapped[reference] ?? reference
            }
            return copy
        }
        manager.replaceLibrary(profiles: restoredProfiles, commands: restoredCommands,
                               folders: commandFolders ?? [],
                               selectedProfileID: selectedProfileID,
                               startupProfileID: startupProfileID, layer: activeLayer)
    }

    private func validate() throws {
        guard formatVersion == 1 else { throw G13BackupError.unsupportedVersion }
        guard (1...100).contains(profiles.count), commands.count <= 5000,
              customIcons.count <= 200, (1...3).contains(activeLayer) else {
            throw G13BackupError.invalidLibrary("The profile, command, icon, or layer count is out of range.")
        }
        guard Set(profiles.map(\.id)).count == profiles.count,
              Set(commands.map(\.id)).count == commands.count,
              profiles.contains(where: { $0.id == selectedProfileID }),
              startupProfileID.map({ id in profiles.contains(where: { $0.id == id }) }) ?? true else {
            throw G13BackupError.invalidLibrary("Profile or command IDs are missing or duplicated.")
        }
        let folders = commandFolders ?? []
        guard folders.count <= 500,
              Set(folders.map(\.id)).count == folders.count,
              folders.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80 }),
              commands.allSatisfy({ command in
                  guard let folderID = command.folderID else { return true }
                  return folders.contains(where: {
                      $0.id == folderID &&
                      $0.applicationBundleID?.lowercased() == command.applicationBundleID?.lowercased()
                  })
              }) else {
            throw G13BackupError.invalidLibrary("A command folder is missing or invalid.")
        }
        for command in commands {
            guard !command.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  command.name.count <= 200, (1...16).contains(command.steps.count),
                  (25...1000).contains(command.delayMilliseconds),
                  command.steps.allSatisfy({ KeyAction.parse($0) != nil }) else {
                throw G13BackupError.invalidLibrary("A named command contains an invalid shortcut.")
            }
        }
        for profile in profiles {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  profile.name.count <= 200 else {
                throw G13BackupError.invalidLibrary("A profile name is missing or too long.")
            }
            let mappings = [profile.keyMapping, profile.m2KeyMapping ?? [:], profile.m3KeyMapping ?? [:],
                            profile.joystickMapping, profile.m2JoystickMapping ?? [:], profile.m3JoystickMapping ?? [:]]
            for mapping in mappings where mapping.count <= 100 {
                for value in mapping.values where !value.isEmpty {
                    guard value.count <= 100,
                          (value.hasPrefix("@")
                           ? UUID(uuidString: String(value.dropFirst())) != nil
                           : KeyAction.parse(value) != nil) else {
                        throw G13BackupError.invalidLibrary("An assignment contains an invalid command ID or shortcut.")
                    }
                }
            }
            guard mappings.allSatisfy({ $0.count <= 100 }) else {
                throw G13BackupError.invalidLibrary("A profile has too many assignments.")
            }
        }
        let references = Self.allIconReferences(profiles: profiles, commands: commands)
        for reference in references where reference.hasPrefix("custom:") {
            guard let icon = customIcons[reference], icon.count <= 4_000_000,
                  Self.isValidCustomReference(reference) else {
                throw G13BackupError.invalidLibrary("A custom icon is missing or invalid.")
            }
        }
        guard customIcons.keys.allSatisfy({ references.contains($0) && Self.isValidCustomReference($0) }) else {
            throw G13BackupError.invalidLibrary("The backup contains an unexpected icon.")
        }
    }

    private static func allIconReferences(profiles: [G13Profile], commands: [G13Command]) -> Set<String> {
        var result = Set(commands.compactMap(\.iconReference))
        for profile in profiles {
            for icons in [profile.keyIcons, profile.m2KeyIcons, profile.m3KeyIcons] {
                result.formUnion(icons?.values ?? Dictionary<String, String>().values)
            }
        }
        return result
    }

    private static func isValidCustomReference(_ reference: String) -> Bool {
        guard reference.hasPrefix("custom:") else { return false }
        let filename = String(reference.dropFirst("custom:".count))
        return filename.hasSuffix(".png") && UUID(uuidString: String(filename.dropLast(4))) != nil
    }

    private func remap(_ icons: [String: String]?, using references: [String: String]) -> [String: String]? {
        icons?.mapValues { references[$0] ?? $0 }
    }
}
