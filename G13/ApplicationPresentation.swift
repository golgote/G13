import AppKit
import UniformTypeIdentifiers

struct ApplicationPresentation {
    let name: String
    let icon: NSImage?

    static func resolve(bundleID: String, savedName: String? = nil) -> ApplicationPresentation {
        let running = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let bundle = url.flatMap { Bundle(url: $0) }
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fallback = bundleID.caseInsensitiveCompare("com.avid.protools") == .orderedSame
            ? "Pro Tools" : bundleID
        let name = savedName ?? running?.localizedName ?? bundleName ?? fallback
        let icon = running?.icon ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        return ApplicationPresentation(name: name, icon: icon)
    }

    static func chooseInstalledApplication() -> (bundleID: String, name: String)? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "app")].compactMap { $0 }
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = "Choose an application for this profile"
        guard panel.runModal() == .OK, let url = panel.url,
              url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            return nil
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return (bundleID, name)
    }
}
