import Foundation

struct G13ProfileWarnings {
    let unassignedKeys: [String]
    let destructiveAssignments: [String]
}

extension ProfileManager {
    var activeWarnings: G13ProfileWarnings {
        guard let profile = activeProfile else {
            return G13ProfileWarnings(unassignedKeys: [], destructiveAssignments: [])
        }
        let mapping: [String: String]
        switch activeLayer {
        case 2: mapping = profile.m2KeyMapping ?? [:]
        case 3: mapping = profile.m3KeyMapping ?? [:]
        default: mapping = profile.keyMapping
        }
        let unassigned = (1...22).map { "G\($0)" }.filter {
            guard let value = mapping[$0]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return true }
            if value.hasPrefix("@") { return command(for: value) == nil }
            return KeyAction.parse(value) == nil
        }
        let dangerWords = ["discard", "delete", "erase", "clear session"]
        let dangerous = mapping.keys.sorted().compactMap { control -> String? in
            guard let assignment = mapping[control], !assignment.isEmpty else { return nil }
            let command = command(for: assignment)
            let steps = command?.steps ?? [assignment]
            let name = command?.name ?? assignment
            let hasRiskyName = dangerWords.contains { name.localizedCaseInsensitiveContains($0) }
            let discardsTake = steps.contains { $0.uppercased() == "CMD+PERIOD" || $0.uppercased() == "CMD+." }
            return hasRiskyName || discardsTake ? "\(control): \(name)" : nil
        }
        return G13ProfileWarnings(unassignedKeys: unassigned, destructiveAssignments: dangerous)
    }
}
