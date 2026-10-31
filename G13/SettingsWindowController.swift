import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(runtime: G13Runtime, openRecorder: Bool = false) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 715),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            newWindow.title = "G13 Studio"
            newWindow.contentView = NSHostingView(rootView: StudioView(runtime: runtime))
            newWindow.center()
            newWindow.isReleasedWhenClosed = false
            newWindow.isRestorable = false
            window = newWindow
            newWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        if openRecorder {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .g13OpenRecorder, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let g13OpenRecorder = Notification.Name("g13OpenRecorder")
}
