import Foundation

@main
struct MouseCommandTests {
    static func main() throws {
        let suite = "G13MouseCommandTests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = ProfileManager(defaults: defaults)
        let startingCount = manager.commands.count
        manager.saveCommand(G13Command(name: "Invalid mouse action", kind: .mouseFunction, steps: []))
        assert(manager.commands.count == startingCount)

        for action in G13MouseAction.allCases {
            var command = G13Command(name: action.label, kind: .mouseFunction, steps: [])
            command.mouseAction = action
            assert(command.isValidAction)
            manager.saveCommand(command)
            assert(manager.commands.contains(where: { $0.id == command.id }))
            assert(manager.assignVisibleCommand(command.assignment, to: "G1", isJoystick: false))
        }

        var shiftedClick = G13Command(name: "Shift-click", kind: .mouseFunction, steps: [])
        shiftedClick.mouseAction = .leftClick
        shiftedClick.mouseModifiers = [.shift]
        manager.saveCommand(shiftedClick)

        let reloaded = ProfileManager(defaults: defaults)
        assert(reloaded.commands.count == startingCount + G13MouseAction.allCases.count + 1)
        assert(reloaded.commands.first(where: { $0.id == shiftedClick.id })?.mouseModifiers == [.shift])
        for action in G13MouseAction.allCases {
            assert(reloaded.commands.contains { $0.mouseAction == action && $0.isValidAction })
        }
        print("Mouse command tests passed")
    }
}
