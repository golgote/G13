import Foundation

private struct LegacyProfile: Encodable {
    let id = UUID()
    let name = "Legacy"
    let keyMapping = ["G1": "A"]
    let joystickMapping: [String: String] = [:]
    let backlightR = 0
    let backlightG = 80
    let backlightB = 255
    let joystickDeadzone = 20
}

private struct LegacyCommand: Encodable {
    let id = UUID()
    let name = "Old command"
    let kind = "keystroke"
    let steps = ["SPACE"]
    let delayMilliseconds = 50
}

@main
struct StudioProfileTests {
    static func main() throws {
        let suite = "G13StudioTests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([LegacyProfile()]), forKey: "profiles")
        defaults.set(try JSONEncoder().encode([LegacyCommand()]), forKey: "namedCommands")

        let manager = ProfileManager(defaults: defaults)
        assert(manager.activeProfileIsUniversal)
        assert(manager.commands.count == 33)
        assert(manager.commandsVisibleInActiveProfile().count == 1)
        let proToolsCommands = manager.commands.filter { $0.applicationBundleID == "com.avid.protools" }
        assert(proToolsCommands.count == 32)
        assert(manager.folders(for: "com.avid.protools").count == 5)
        assert(proToolsCommands.allSatisfy { $0.folderID != nil })
        assert(proToolsCommands.first { $0.name == "Duplicate in Front" }?.steps == ["CTRL+ALT+K"])
        assert(proToolsCommands.first { $0.name == "Duplicate in Front" }?.iconReference == "studio:duplicate-front")
        assert(proToolsCommands.first { $0.name == "Zoom In" }?.iconReference == "sf:plus.magnifyingglass")
        assert(proToolsCommands.first { $0.name == "Zoom Out" }?.iconReference == "sf:minus.magnifyingglass")
        assert(proToolsCommands.first { $0.name == "Save Session As" }?.iconReference == "studio:save-as")
        assert(proToolsCommands.first { $0.name == "Stop & Discard Take" }?.steps == ["CMD+PERIOD"])
        assert(proToolsCommands.first { $0.name == "Increase Clip Gain" }?.steps == ["CTRL+SHIFT+UP"])
        assert(proToolsCommands.first { $0.name == "Decrease Clip Gain" }?.steps == ["CTRL+SHIFT+DOWN"])
        assert(proToolsCommands.first { $0.name == "Nudge Right" }?.steps == ["NUMPADPLUS"])
        assert(proToolsCommands.first { $0.name == "Slip Mode" }?.steps == ["F2"])
        assert(proToolsCommands.first { $0.name == "Spot Mode" }?.steps == ["F3"])
        assert(proToolsCommands.first { $0.name == "Smart Tool" }?.steps == ["CMD+7"])
        manager.bindActiveProfile(to: "com.avid.test")
        assert(manager.activeProfile?.applicationBundleID == nil)
        manager.deleteProfile(at: 0)
        assert(manager.profiles.count == 1)
        assert(manager.keyMapping["G1"]?.keycode == KeyAction.parse("A")?.keycode)
        manager.switchLayer(2)
        assert(manager.keyMapping.isEmpty)
        assert(manager.backlightR == 0 && manager.backlightG == 80 && manager.backlightB == 255)
        manager.setBacklightColor(G13BacklightColor(red: 255, green: 20, blue: 0))
        assert(manager.backlightR == 255 && manager.backlightG == 20 && manager.backlightB == 0)
        manager.setKey("G1", to: "CMD+S")
        assert(manager.keyMapping["G1"]?.command == true)
        manager.switchLayer(1)
        assert(manager.keyMapping["G1"]?.keycode == KeyAction.parse("A")?.keycode)
        assert(manager.backlightR == 0 && manager.backlightG == 80 && manager.backlightB == 255)
        manager.switchLayer(3)
        assert(manager.backlightR == 0 && manager.backlightG == 80 && manager.backlightB == 255)
        manager.setBacklightColor(G13BacklightColor(red: 0, green: 255, blue: 30))
        assert(manager.backlightG == 255)
        manager.switchLayer(2)
        assert(manager.backlightR == 255 && manager.backlightG == 20)
        manager.switchLayer(1)

        let command = G13Command(name: "Save", kind: .keystroke, steps: ["CMD+S"])
        manager.saveCommand(command)
        manager.setKey("G2", to: command.assignment)
        assert(manager.keyMapping["G2"]?.command == true)
        assert(manager.assignVisibleCommand(command.assignment, to: "G3", isJoystick: false))
        assert(manager.keyMapping["G3"]?.command == true)
        manager.setIconReference("sf:playpause.fill", for: "G2", isJoystick: false)
        assert(manager.iconReference(for: "G2", isJoystick: false) == "sf:playpause.fill")
        manager.activeJoystickMode = .twoAxisScroll
        manager.activeJoystickScrollSpeed = 4
        manager.activeJoystickHorizontalScrollSpeed = 3
        assert(G13JoystickMode.verticalScroll.scrolls("UP"))
        assert(!G13JoystickMode.verticalScroll.scrolls("LEFT"))
        assert(G13JoystickMode.horizontalScroll.scrolls("RIGHT"))
        assert(!G13JoystickMode.horizontalScroll.scrolls("DOWN"))
        assert(G13JoystickMode.twoAxisScroll.scrolls("LEFT"))
        manager.switchLayer(2)
        manager.activeJoystickMode = .verticalScroll
        manager.switchLayer(3)
        manager.activeJoystickMode = .horizontalScroll
        manager.switchLayer(1)
        assert(manager.activeJoystickMode == .twoAxisScroll)

        assert(manager.duplicateActiveProfile() == 1)
        assert(!manager.activeProfileIsUniversal)
        assert(manager.keyMapping["G2"]?.command == true)
        assert(manager.iconReference(for: "G2", isJoystick: false) == "sf:playpause.fill")
        assert(manager.activeJoystickMode == .twoAxisScroll)
        assert(manager.activeJoystickScrollSpeed == 4)
        assert(manager.activeJoystickHorizontalScrollSpeed == 3)
        manager.bindActiveProfile(to: "com.avid.test", displayName: "Pro Tools")
        assert(manager.autoSwitchEnabled)
        manager.setAutoSwitchEnabled(false)
        manager.activateProfile(for: "com.other.test")
        assert(!manager.activeProfileIsUniversal && manager.keyMapping["G2"] != nil)
        manager.activateProfile(for: "com.avid.test")
        assert(!manager.activeProfileIsUniversal)
        manager.setAutoSwitchEnabled(true)
        manager.switchToProfile(at: 0)
        manager.activateProfile(for: "com.other.test")
        assert(manager.activeProfileIsUniversal)
        manager.activateProfile(for: "com.avid.test")
        assert(manager.activeProfileIndex == 1)
        manager.activateProfile(for: "com.other.test")
        assert(manager.activeProfileIndex == 1)
        assert(!manager.inputSuppressed && manager.keyMapping["G2"] != nil)
        manager.setStartupProfileToActive()
        assert(manager.activeIsStartupProfile)

        let reloaded = ProfileManager(defaults: defaults)
        assert(reloaded.activeProfileIndex == 1)
        assert(reloaded.activeIsStartupProfile)
        assert(reloaded.commands.count == 34)
        assert(reloaded.folders(for: "com.avid.protools").count == 5)
        assert(reloaded.profiles[0].m2KeyMapping?["G1"] == "CMD+S")
        assert(reloaded.profiles[0].m2BacklightColor == G13BacklightColor(red: 255, green: 20, blue: 0))
        assert(reloaded.profiles[0].m3BacklightColor == G13BacklightColor(red: 0, green: 255, blue: 30))
        assert(reloaded.profiles[0].isUniversalDefault == true)
        assert(reloaded.profiles[1].applicationBundleID == "com.avid.test")
        assert(reloaded.profiles[1].applicationDisplayName == "Pro Tools")
        assert(reloaded.profiles[1].autoSwitch == true)
        assert(reloaded.profiles[1].joystickMode == .twoAxisScroll)
        assert(reloaded.profiles[1].m2JoystickMode == .verticalScroll)
        assert(reloaded.profiles[1].m3JoystickMode == .horizontalScroll)
        assert(reloaded.profiles[1].joystickScrollSpeed == 4)
        assert(reloaded.profiles[1].joystickHorizontalScrollSpeed == 3)
        assert(reloaded.profiles[1].keyIcons?["key:G2"] == "sf:playpause.fill")

        // Moving a command into an app scope must disable old assignments in Default.
        manager.switchToProfile(at: 0)
        var scopedCommand = command
        scopedCommand.applicationBundleID = "com.avid.test"
        manager.saveCommand(scopedCommand)
        assert(manager.command(for: command.assignment) == nil)
        assert(manager.keyMapping["G2"] == nil)
        manager.switchToProfile(at: 1)
        assert(manager.command(for: command.assignment) != nil)
        assert(manager.keyMapping["G2"]?.command == true)
        let firstFolder = manager.addCommandFolder(name: "First", applicationBundleID: "com.avid.test")!
        let secondFolder = manager.addCommandFolder(name: "Second", applicationBundleID: "com.avid.test")!
        let allAppsFolder = manager.addCommandFolder(name: "All Apps Test", applicationBundleID: nil)!
        assert(manager.moveCommand(command.assignment, toFolder: firstFolder.id))
        assert(manager.moveCommand(command.assignment, toFolder: secondFolder.id))
        assert(manager.commands.first { $0.id == command.id }?.folderID == secondFolder.id)
        assert(!manager.moveCommand(command.assignment, toFolder: allAppsFolder.id))
        assert(manager.keyMapping["G2"]?.command == true)
        manager.deleteProfile(at: 1)
        assert(manager.startupProfileID == manager.activeProfile?.id)
        assert(manager.activeProfileIsUniversal)

        let boundOnlySuite = "G13StudioTests." + UUID().uuidString
        guard let boundOnlyDefaults = UserDefaults(suiteName: boundOnlySuite) else { fatalError("No test defaults") }
        defer { boundOnlyDefaults.removePersistentDomain(forName: boundOnlySuite) }
        var boundOnly = G13Profile(name: "Pro Tools")
        boundOnly.applicationBundleID = "com.avid.test"
        boundOnlyDefaults.set(try JSONEncoder().encode([boundOnly]), forKey: "profiles")
        let migrated = ProfileManager(defaults: boundOnlyDefaults)
        assert(migrated.profiles.count == 2)
        assert(migrated.profiles[0].isUniversalDefault == true)
        assert(migrated.profiles[0].keyMapping.isEmpty)
        assert(migrated.profiles[1].applicationBundleID == "com.avid.test")
        let proToolsSuite = "G13StudioTests." + UUID().uuidString
        guard let proToolsDefaults = UserDefaults(suiteName: proToolsSuite) else { fatalError("No test defaults") }
        defer { proToolsDefaults.removePersistentDomain(forName: proToolsSuite) }
        let proTools = ProfileManager(defaults: proToolsDefaults)
        assert(proTools.commandsVisibleInActiveProfile().isEmpty)
        proTools.addProfile(name: "Pro Tools")
        proTools.switchToProfile(at: 1)
        proTools.bindActiveProfile(to: "com.avid.protools", displayName: "Pro Tools")
        assert(proTools.commandsVisibleInActiveProfile().count == 32)
        let frontDuplicate = proTools.commands.first { $0.name == "Duplicate in Front" }!
        assert(proTools.assignVisibleCommand(frontDuplicate.assignment, to: "G1", isJoystick: false))
        assert(proTools.keyMapping["G1"]?.control == true)
        proTools.switchToProfile(at: 0)
        assert(proTools.commandsVisibleInActiveProfile().isEmpty)
        assert(!proTools.assignVisibleCommand(frontDuplicate.assignment, to: "G1", isJoystick: false))
        proTools.setKey("G2", to: "SPACE")
        proTools.switchToProfile(at: 1)
        for layer in 1...3 {
            proTools.switchLayer(layer)
            proTools.setKey("G1", to: "SPACE")
            proTools.setIconReference("sf:star", for: "G1", isJoystick: false)
            assert(proTools.assignVisibleCommand(frontDuplicate.assignment, to: "G1", isJoystick: false))
            assert(proTools.iconReference(for: "G1", isJoystick: false) == nil)
            assert(proTools.activeRawKeyMapping["G1"] == frontDuplicate.assignment)
            proTools.setIconReference("sf:star", for: "G1", isJoystick: false)
            proTools.clearKey("G1")
            assert(proTools.activeRawKeyMapping["G1"] == nil)
            assert(proTools.iconReference(for: "G1", isJoystick: false) == nil)
            proTools.setKey("LEFT", to: "F1")
            proTools.setIconReference("sf:star", for: "LEFT", isJoystick: false)
            proTools.clearKey("LEFT")
            assert(proTools.iconReference(for: "LEFT", isJoystick: false) == nil)
            proTools.setJoystickDirection("UP", to: "UP")
            proTools.setIconReference("sf:star", for: "UP", isJoystick: true)
            proTools.clearJoystickDirection("UP")
            assert(proTools.iconReference(for: "UP", isJoystick: true) == nil)
        }
        proTools.switchLayer(1)
        proTools.setKey("G1", to: "CMD+E")
        proTools.activateProfile(for: "com.avid.protools")
        assert(proTools.outputProfileIndex == 1)
        assert(proTools.outputKeyMapping["G1"]?.command == true)
        proTools.switchToProfile(at: 0)
        assert(proTools.outputProfileIndex == 0)
        proTools.activateProfile(for: "com.avid.protools")
        assert(proTools.outputProfileIndex == 0)
        proTools.switchToProfile(at: 1)
        assert(proTools.outputProfileIndex == 1)
        proTools.activateProfile(for: "com.example.browser")
        assert(proTools.activeProfileIndex == 1)
        assert(proTools.outputProfileIndex == 0)
        assert(proTools.outputKeyMapping["G1"] == nil)
        assert(proTools.outputKeyMapping["G2"]?.keycode == KeyAction.parse("SPACE")?.keycode)
        proTools.setEditorFrontmost()
        assert(proTools.outputProfile == nil && proTools.outputKeyMapping.isEmpty)
        assert(proTools.activeRawKeyMapping["G1"] == "CMD+E")
        let reloadedProTools = ProfileManager(defaults: proToolsDefaults)
        assert(reloadedProTools.commands.count == 32)
        proTools.activateProfile(for: "com.avid.protools")
        assert(proTools.assignVisibleCommand(frontDuplicate.assignment, to: "G1", isJoystick: false))
        proTools.setIconReference("sf:star", for: "G1", isJoystick: false)
        proTools.deleteCommand(frontDuplicate)
        assert(proTools.activeRawKeyMapping["G1"] == nil)
        assert(proTools.iconReference(for: "G1", isJoystick: false) == nil)

        let upgradeSuite = "G13StudioTests." + UUID().uuidString
        guard let upgradeDefaults = UserDefaults(suiteName: upgradeSuite) else { fatalError("No test defaults") }
        defer { upgradeDefaults.removePersistentDomain(forName: upgradeSuite) }
        upgradeDefaults.set(true, forKey: "proToolsCommandLibrarySeeded")
        upgradeDefaults.set(true, forKey: "frontDuplicateCommandSeeded")
        upgradeDefaults.set(try JSONEncoder().encode([LegacyCommand()]), forKey: "namedCommands")
        let upgraded = ProfileManager(defaults: upgradeDefaults)
        assert(upgraded.commands.count == 15)
        assert(upgraded.commands.contains { $0.name == "Stop & Discard Take" })
        assert(ProfileManager(defaults: upgradeDefaults).commands.count == 15)
        let iconSuite = "G13StudioTests." + UUID().uuidString
        guard let iconDefaults = UserDefaults(suiteName: iconSuite) else { fatalError("No test defaults") }
        defer { iconDefaults.removePersistentDomain(forName: iconSuite) }
        iconDefaults.set(true, forKey: "proToolsCommandLibrarySeeded")
        iconDefaults.set(true, forKey: "frontDuplicateCommandSeeded")
        iconDefaults.set(true, forKey: "proToolsAdditionalCommandsSeeded")
        var oldZoom = G13Command(name: "Zoom In", kind: .keystroke, steps: ["CMD+]"])
        oldZoom.applicationBundleID = "com.avid.protools"
        oldZoom.iconReference = "sf:magnifyingglass"
        var customSave = G13Command(name: "Save Session As", kind: .keystroke, steps: ["CMD+CTRL+S"])
        customSave.applicationBundleID = "com.avid.protools"
        customSave.iconReference = "sf:star"
        iconDefaults.set(try JSONEncoder().encode([oldZoom, customSave]), forKey: "namedCommands")
        let refined = ProfileManager(defaults: iconDefaults)
        assert(refined.commands.first { $0.name == "Zoom In" }?.iconReference == "sf:plus.magnifyingglass")
        assert(refined.commands.first { $0.name == "Save Session As" }?.iconReference == "sf:star")
        assert(ProfileManager(defaults: iconDefaults).commands.count == 2)
        print("Studio profile tests passed")
    }
}
