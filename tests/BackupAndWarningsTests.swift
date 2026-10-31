import Foundation

// The app's image decoder is tested by the Xcode build. These library tests
// use no custom images, so only the backup API surface is needed here.
enum G13IconStore {
    static func backupData(for reference: String) throws -> Data { Data() }
    static func restoreBackupData(_ data: Data) throws -> String { "custom:" + UUID().uuidString + ".png" }
}

@main
struct BackupAndWarningsTests {
    static func main() throws {
        let sourceName = "G13BackupSource." + UUID().uuidString
        let targetName = "G13BackupTarget." + UUID().uuidString
        guard let sourceDefaults = UserDefaults(suiteName: sourceName),
              let targetDefaults = UserDefaults(suiteName: targetName) else { fatalError("No test defaults") }
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceName)
            targetDefaults.removePersistentDomain(forName: targetName)
        }
        let source = ProfileManager(defaults: sourceDefaults)
        assert(source.activeWarnings.unassignedKeys.count == 22)
        source.setKey("G1", to: "SPACE")
        assert(source.activeWarnings.unassignedKeys.count == 21)
        source.addProfile(name: "Pro Tools")
        source.switchToProfile(at: 1)
        source.bindActiveProfile(to: "com.avid.protools", displayName: "Pro Tools")
        source.setStartupProfileToActive()
        let folder = source.addCommandFolder(name: "My custom", applicationBundleID: "com.avid.protools")!
        assert(source.addCommandFolder(name: "my CUSTOM", applicationBundleID: "com.avid.protools") == nil)
        var play = G13Command(name: "Play", kind: .keystroke, steps: ["SPACE"])
        play.applicationBundleID = "com.avid.protools"
        play.folderID = folder.id
        source.saveCommand(play)
        assert(source.commands.first(where: { $0.id == play.id })?.folderID == folder.id)
        let discard = source.commands.first { $0.name == "Stop & Discard Take" }!
        source.setKey("G2", to: discard.assignment)
        assert(source.activeWarnings.destructiveAssignments == ["G2: Stop & Discard Take"])
        source.switchLayer(2)
        source.setBacklightColor(G13BacklightColor(red: 200, green: 10, blue: 4))
        source.activeJoystickScrollSpeed = 4
        source.activeJoystickHorizontalScrollSpeed = 3
        assert(source.activeWarnings.destructiveAssignments.isEmpty)

        let data = try G13ProfileBackup.create(from: source)
        let archive = try G13ProfileBackup.read(data)
        let target = ProfileManager(defaults: targetDefaults)
        try archive.restore(into: target)
        assert(target.profiles.count == 2)
        assert(target.activeProfileName == "Pro Tools")
        assert(target.startupProfileID == source.startupProfileID)
        assert(target.activeLayer == 2)
        assert(target.activeProfile?.m2BacklightColor == G13BacklightColor(red: 200, green: 10, blue: 4))
        assert(target.activeJoystickScrollSpeed == 4)
        assert(target.activeJoystickHorizontalScrollSpeed == 3)
        assert(target.activeProfile?.keyMapping["G2"] == discard.assignment)
        assert(target.commands.count == source.commands.count)
        assert(target.commandFolders == source.commandFolders)
        assert(target.commands.first(where: { $0.id == play.id })?.folderID == folder.id)
        target.deleteCommandFolder(folder.id)
        assert(target.commands.first(where: { $0.id == play.id })?.folderID == nil)
        assert(!target.commandFolders.contains(where: { $0.id == folder.id }))
        target.switchLayer(1)
        assert(target.activeWarnings.destructiveAssignments.count == 1)
        target.setKey("G3", to: "CMD+PERIOD")
        assert(target.activeWarnings.destructiveAssignments.count == 2)
        target.deleteCommand(discard)
        assert(target.activeProfile?.keyMapping["G2"] == nil)
        assert(target.activeWarnings.unassignedKeys.contains("G2"))
        assert(target.activeWarnings.destructiveAssignments.count == 1)

        var badVersion = archive
        badVersion = G13ProfileBackup(formatVersion: 99, profiles: badVersion.profiles,
                                      commands: badVersion.commands, selectedProfileID: badVersion.selectedProfileID,
                                      activeLayer: badVersion.activeLayer, customIcons: [:])
        assert((try? G13ProfileBackup.read(JSONEncoder().encode(badVersion))) == nil)
        assert((try? G13ProfileBackup.read(Data(repeating: 0, count: G13ProfileBackup.maximumFileSize + 1))) == nil)
        print("Backup and warning tests passed")
    }
}
